import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32/win32.dart';
import 'app.dart';
import 'services/item_service.dart';
import 'services/hotkey_service.dart';
import 'services/settings_service.dart';
import 'services/launch_log_service.dart';
import 'utils/tray_icon.dart';

late final SystemTray systemTray;
const MethodChannel _settingsChannel = MethodChannel('quick_launch/settings');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load settings, items, logs
  await SettingsService().load();
  await ItemService().load();
  await LaunchLogService().load();

  // 2. Run the app
  runApp(const QuickLaunchApp());

  // 3. Wait for window ready
  await WidgetsBinding.instance.endOfFrame;

  // 4. Set native window handle for hotkey
  final hWnd = appWindow.handle;
  if (hWnd != null) {
    HotkeyService().setWindowHandle(hWnd);
  }

  // 5. Register all item hotkeys
  for (final item in ItemService().items.value) {
    if (item.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(item);
    }
  }

  // 6. Setup MethodChannel for WM_HOTKEY
  const hotkeyChannel = MethodChannel('quick_launch/hotkey');
  hotkeyChannel.setMethodCallHandler((call) async {
    if (call.method == 'onHotkey') {
      final hotkeyId = call.arguments as int;
      HotkeyService().onHotkeyPressed(hotkeyId);
    }
    return null;
  });

  // 7. Setup callback: when show-window hotkey fires, bring window to front
  HotkeyService().onShowWindow = () {
    final hwnd = appWindow.handle;
    if (hwnd != null) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
  };

  // 8. Register show-window hotkey if configured
  final showMods = SettingsService().showWindowModifiers.value;
  final showKey = SettingsService().showWindowKey.value;
  if (showMods != null && showKey != null) {
    HotkeyService().registerShowWindowHotkey(showMods, showKey);
  }

  // 9. Listen for show-window hotkey changes from settings
  SettingsService().showWindowModifiers.addListener(() {
    HotkeyService().unregisterShowWindowHotkey();
    final m = SettingsService().showWindowModifiers.value;
    final k = SettingsService().showWindowKey.value;
    if (m != null && k != null) {
      HotkeyService().registerShowWindowHotkey(m, k);
    }
  });

  // 10. Sync settings to native
  await _syncSettingsToNative();

  // 11. Init system tray
  await _initSystemTray();

  // 12. Apply always-on-top
  if (SettingsService().alwaysOnTop.value) {
    _setTopmost(true);
  }

  // 13. Hide on startup (last so no flash)
  if (SettingsService().hideOnStartup.value) {
    appWindow.hide();
  }
}

void _setTopmost(bool on) {
  final hwnd = appWindow.handle;
  if (hwnd != null) {
    SetWindowPos(hwnd, on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE);
  }
}

Future<void> _syncSettingsToNative() async {
  await _settingsChannel.invokeMethod(
    'setMinimizeToTray',
    SettingsService().minimizeToTray.value,
  );
  SettingsService().minimizeToTray.addListener(() {
    _settingsChannel.invokeMethod(
      'setMinimizeToTray',
      SettingsService().minimizeToTray.value,
    );
  });
}

Future<void> _initSystemTray() async {
  systemTray = SystemTray();

  final iconPath = await TrayIconHelper.saveIconToFile();

  await systemTray.initSystemTray(
    iconPath: iconPath,
    title: '快速启动',
    toolTip: '快速启动',
  );

  final menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(
      label: '显示',
      onClicked: (_) => appWindow.show(),
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: '退出',
      onClicked: (_) async {
        HotkeyService().dispose();
        await _settingsChannel.invokeMethod('requestExit');
      },
    ),
  ]);
  await systemTray.setContextMenu(menu);

  systemTray.registerSystemTrayEventHandler((event) {
    if (event == kSystemTrayEventClick) {
      appWindow.show();
    } else if (event == kSystemTrayEventRightClick) {
      systemTray.popUpContextMenu();
    }
  });
}
