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
import 'services/group_service.dart';
import 'utils/tray_icon.dart';

late final SystemTray systemTray;
const MethodChannel _settingsChannel = MethodChannel('quick_launch/settings');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load settings, items, logs
  try {
    await SettingsService().load();
  } catch (e) {
    // ignore: avoid_print
    print('加载设置失败: $e');
  }
  try {
    await ItemService().load();
  } catch (e) {
    // ignore: avoid_print
    print('加载启动项失败: $e');
  }
  try {
    await LaunchLogService().load();
  } catch (e) {
    // ignore: avoid_print
    print('加载日志失败: $e');
  }
  try {
    await GroupService().load();
  } catch (e) {
    // ignore: avoid_print
    print('加载分组失败: $e');
  }

  // 2. Run the app
  runApp(const QuickLaunchApp());

  // 3. Wait for window and complete all startup tasks.
  //    Wrap everything in one try-catch so no single failure kills the app.
  try {
    await _startupAfterRunApp();
  } catch (e) {
    // ignore: avoid_print
    print('启动后初始化失败: $e');
  }
}

/// 所有 runApp 之后的初始化步骤，集中统一起见，任何异常不会导致应用退出。
Future<void> _startupAfterRunApp() async {
  // 3. Send hideOnStartup to native BEFORE first frame renders
  if (SettingsService().hideOnStartup.value) {
    await _settingsChannel.invokeMethod('setHideOnStartup', true);
  }

  // 4. Wait for window ready
  await WidgetsBinding.instance.endOfFrame;

  // 5. Set native window handle for hotkey
  final hWnd = appWindow.handle;
  if (hWnd != null) {
    HotkeyService().setWindowHandle(hWnd);
  }

  // 6. Register all item hotkeys
  for (final item in ItemService().items.value) {
    if (item.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(item);
    }
  }

  // 7. Setup MethodChannel for WM_HOTKEY
  const hotkeyChannel = MethodChannel('quick_launch/hotkey');
  hotkeyChannel.setMethodCallHandler((call) async {
    if (call.method == 'onHotkey') {
      final hotkeyId = call.arguments as int;
      HotkeyService().onHotkeyPressed(hotkeyId);
    }
    return null;
  });

  // 8. Setup callback: when show-window hotkey fires, bring window to front
  HotkeyService().onShowWindow = () {
    final hwnd = appWindow.handle;
    if (hwnd != null) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
  };

  // 8b. Setup callback: when group hotkey fires, bring window to front
  HotkeyService().onGroupHotkey = (groupId) {
    final hwnd = appWindow.handle;
    if (hwnd != null) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
  };

  // 8c. Setup callback: when search hotkey fires, bring window to front
  HotkeyService().onSearchHotkey = () {
    // 窗口显示由 HomePage._onSearchHotkeyTriggered 在弹出搜索前处理
  };

  // 9. Register show-window hotkey if configured
  final showMods = SettingsService().showWindowModifiers.value;
  final showKey = SettingsService().showWindowKey.value;
  if (showMods != null && showKey != null) {
    HotkeyService().registerShowWindowHotkey(showMods, showKey);
  }

  // 9b. Register all group hotkeys
  GroupService().loadAllGroupHotkeys();

  // 9c. Register search hotkey if configured
  final searchMods = SettingsService().searchHotkeyModifiers.value;
  final searchKey = SettingsService().searchHotkeyKey.value;
  if (searchMods != null && searchKey != null) {
    HotkeyService().registerSearchHotkey(searchMods, searchKey);
  }

  // 10. Listen for show-window hotkey changes from settings
  SettingsService().showWindowModifiers.addListener(() {
    HotkeyService().unregisterShowWindowHotkey();
    final m = SettingsService().showWindowModifiers.value;
    final k = SettingsService().showWindowKey.value;
    if (m != null && k != null) {
      HotkeyService().registerShowWindowHotkey(m, k);
    }
  });

  // 10b. Listen for search hotkey changes from settings
  SettingsService().searchHotkeyModifiers.addListener(() {
    HotkeyService().unregisterSearchHotkey();
    final m = SettingsService().searchHotkeyModifiers.value;
    final k = SettingsService().searchHotkeyKey.value;
    if (m != null && k != null) {
      HotkeyService().registerSearchHotkey(m, k);
    }
  });

  // 11. Sync settings to native
  await _syncSettingsToNative();

  // 12. Init system tray (always default icon)
  await _initSystemTray();

  // 13. Apply saved custom icon to both window and tray (if any)
  await _applySavedCustomIcon();

  // 14. Listen for runtime custom icon changes → update tray
  SettingsService().customIconPath.addListener(_onCustomIconChanged);

  // 15. Apply always-on-top
  if (SettingsService().alwaysOnTop.value) {
    _setTopmost(true);
  }

  // 16. Check for updates
  if (await UpdateService().checkForUpdate()) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        UpdateService().showUpdateDialog(context);
      }
    });
  }

  // 17. Hide on startup (last so no flash)
  if (SettingsService().hideOnStartup.value) {
    final hwnd = appWindow.handle;
    if (hwnd != null) {
      ShowWindow(hwnd, SW_HIDE);
    }
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _settingsChannel.invokeMethod('showBalloon', {
        'title': '快速启动',
        'message': '程序已在系统托盘后台运行，点击托盘图标即可显示。',
      });
    } catch (_) {}
  }
}

Future<void> _applySavedCustomIcon() async {
  final path = SettingsService().customIconPath.value;
  if (path == null || path.isEmpty || !File(path).existsSync()) return;

  // Try window icon first
  bool windowOk = false;
  try {
    final ok = await _settingsChannel.invokeMethod<bool>('setAppIcon', path);
    windowOk = ok == true;
  } catch (_) {}

  // Then try tray icon
  bool trayOk = false;
  try {
    await systemTray.setSystemTrayInfo(iconPath: path);
    trayOk = true;
  } catch (_) {}

  // Both failed → clear config so next startup doesn't retry
  if (!windowOk && !trayOk) {
    await SettingsService().setCustomIconPath(null);
  }
}

void _onCustomIconChanged() async {
  try {
    final newPath = SettingsService().customIconPath.value;
    if (newPath != null && newPath.isNotEmpty && File(newPath).existsSync()) {
      await systemTray.setSystemTrayInfo(iconPath: newPath);
    } else {
      final defaultIcon = await TrayIconHelper.saveIconToFile();
      await systemTray.setSystemTrayInfo(iconPath: defaultIcon);
    }
  } catch (_) {
    // Tray update failed → restore default
    final defaultIcon = await TrayIconHelper.saveIconToFile();
    try {
      await systemTray.setSystemTrayInfo(iconPath: defaultIcon);
    } catch (_) {}
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
  try {
    await _settingsChannel.invokeMethod(
      'setMinimizeToTray',
      SettingsService().minimizeToTray.value,
    );
  } catch (_) {}
  SettingsService().minimizeToTray.addListener(() {
    _settingsChannel.invokeMethod(
      'setMinimizeToTray',
      SettingsService().minimizeToTray.value,
    );
  });
}

Future<void> _initSystemTray() async {
  try {
    systemTray = SystemTray();

    // 重要：始终用默认图标初始化托盘，确保托盘 100% 能正常工作。
    // 自定义图标在初始化完成后通过 setSystemTrayInfo 切换。
    final defaultIcon = await TrayIconHelper.saveIconToFile();
    await systemTray.initSystemTray(
      iconPath: defaultIcon,
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
  } catch (_) {
    // 托盘初始化失败不阻止应用运行
  }
}
