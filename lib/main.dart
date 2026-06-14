import 'dart:io';
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
import 'services/update_service.dart';
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

  // 3. Send hideOnStartup to native BEFORE first frame renders
  //    so the C++ side can skip Show() in SetNextFrameCallback
  if (SettingsService().hideOnStartup.value) {
    await _settingsChannel.invokeMethod('setHideOnStartup', true);
  }

  // 4. Wait for window ready
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

  // 11. Init system tray (use custom icon if configured)
  await _initSystemTray();

  // 12. Apply custom app icon (window title bar + taskbar)
  try {
    final customIcon = SettingsService().customIconPath.value;
    if (customIcon != null && customIcon.isNotEmpty && File(customIcon).existsSync()) {
      await _settingsChannel.invokeMethod('setAppIcon', customIcon);
    }
  } catch (_) {
    // 忽略图标加载失败，继续启动
  }

  // Listen for custom icon changes (from settings) → update tray icon live
  SettingsService().customIconPath.addListener(() async {
    try {
      final newPath = SettingsService().customIconPath.value;
      if (newPath != null && newPath.isNotEmpty && File(newPath).existsSync()) {
        await systemTray.setSystemTrayInfo(iconPath: newPath);
      } else {
        // Restore default tray icon
        final defaultIcon = await TrayIconHelper.saveIconToFile();
        await systemTray.setSystemTrayInfo(iconPath: defaultIcon);
      }
    } catch (_) {
      // 忽略托盘图标更新失败
    }
  });

  // 13. Apply always-on-top
  if (SettingsService().alwaysOnTop.value) {
    _setTopmost(true);
  }

  // 14. Check for updates (async, non-blocking)
  if (await UpdateService().checkForUpdate()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        UpdateService().showUpdateDialog(context);
      }
    });
  }

  // 15. Hide on startup (last so no flash)
  if (SettingsService().hideOnStartup.value) {
    final hwnd = appWindow.handle;
    if (hwnd != null) {
      ShowWindow(hwnd, SW_HIDE);
    }
    // 等一小会让托盘图标就绪，再弹出通知提示用户
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _settingsChannel.invokeMethod('showBalloon', {
        'title': '快速启动',
        'message': '程序已在系统托盘后台运行，点击托盘图标即可显示。',
      });
    } catch (_) {
      // 气球通知发送失败不影响程序运行
    }
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

  // Use custom icon if configured, otherwise generate the default "Q" icon
  String iconPath;
  final customIcon = SettingsService().customIconPath.value;
  if (customIcon != null && customIcon.isNotEmpty && File(customIcon).existsSync()) {
    iconPath = customIcon;
  } else {
    iconPath = await TrayIconHelper.saveIconToFile();
  }

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
