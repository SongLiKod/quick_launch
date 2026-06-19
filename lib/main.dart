import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32/win32.dart';
import 'app.dart';
import 'models/launch_item.dart';
import 'services/item_service.dart';
import 'services/hotkey_service.dart';
import 'services/settings_service.dart';
import 'services/launch_log_service.dart';
import 'services/update_service.dart';
import 'services/group_service.dart';
import 'utils/tray_icon.dart';
import 'widgets/search_overlay.dart';
import 'widgets/add_item_dialog.dart';

late final SystemTray systemTray;
const MethodChannel _settingsChannel = MethodChannel('quick_launch/settings');
const MethodChannel _filesChannel = MethodChannel('quick_launch/files');

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

  // 7b. Setup MethodChannel for file paths (from context menu / command-line).
  _filesChannel.setMethodCallHandler((call) async {
    if (call.method == 'onFileReceived') {
      final path = call.arguments as String;
      if (path.isNotEmpty) {
        _showAddFileDialog(path);
      }
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

  // 8c. Setup callback: when search hotkey fires, open search overlay
  // SearchOverlay.open() 会自动将窗口设为无边框、缩小居中、显示并推入搜索路由
  HotkeyService().onSearchHotkey = () {
    SearchOverlay.open();
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

  // 10c. Listen for pause hotkey changes from settings
  SettingsService().pauseHotkeyModifiers.addListener(() {
    HotkeyService().unregisterPauseHotkey();
    final m = SettingsService().pauseHotkeyModifiers.value;
    final k = SettingsService().pauseHotkeyKey.value;
    if (m != null && k != null) {
      HotkeyService().registerPauseHotkey(m, k);
    }
  });

  // 10d. Register pause toggle hotkey if configured
  final pauseMods = SettingsService().pauseHotkeyModifiers.value;
  final pauseKey = SettingsService().pauseHotkeyKey.value;
  if (pauseMods != null && pauseKey != null) {
    HotkeyService().registerPauseHotkey(pauseMods, pauseKey);
  }

  // 10e. Listen for pause state changes → update tray appearance
  HotkeyService().paused.addListener(_onPauseStateChanged);

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
    SetWindowPos(
      hwnd,
      on ? HWND_TOPMOST : HWND_NOTOPMOST,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE,
    );
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

    await _updateTrayMenu();
    await _updateTrayPauseState();

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

Future<void> _updateTrayMenu() async {
  final menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(label: '显示', onClicked: (_) => appWindow.show()),
    MenuSeparator(),
    MenuItemLabel(
      label: '重新加载',
      onClicked: (_) async {
        await Process.start(Platform.resolvedExecutable, []);
        HotkeyService().dispose();
        await _settingsChannel.invokeMethod('requestExit');
      },
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: HotkeyService().paused.value ? '✓ 暂停热键' : '  暂停热键',
      onClicked: (_) => HotkeyService().togglePause(),
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
}

Future<void> _updateTrayPauseState() async {
  final paused = HotkeyService().paused.value;
  final toolTip = paused ? '快速启动 - 热键已暂停' : '快速启动';
  try {
    final iconPath = paused
        ? await TrayIconHelper.savePausedIconToFile()
        : await TrayIconHelper.saveIconToFile();
    // 切换托盘图标
    await systemTray.setSystemTrayInfo(iconPath: iconPath, toolTip: toolTip);
    // 切换任务栏窗口图标
    await _settingsChannel.invokeMethod('setAppIcon', iconPath);
  } catch (_) {}
}

void _onPauseStateChanged() {
  _updateTrayMenu();
  _updateTrayPauseState();
}

/// 显示添加启动项对话框（来自右键菜单或命令行参数），含自动去重。
void _showAddFileDialog(String path) {
  final context = navigatorKey.currentContext;
  if (context == null) return;

  // 自动去重：如果路径已存在，提示用户而非重复添加
  final existing = ItemService().items.value.where(
    (item) =>
        item.targetPath.replaceAll('"', '').toLowerCase() ==
        path.replaceAll('"', '').toLowerCase(),
  );
  if (existing.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('已在列表中'),
            content: Text('"${path.split('\\').last}" 已在启动列表中。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    });
    return;
  }

  // 弹出添加对话框，预填路径和名称
  showDialog<LaunchItem>(
    context: context,
    builder: (ctx) => AddItemDialog(initialFile: path),
  ).then((result) {
    if (result != null) {
      ItemService().addItem(result);
      if (result.hotkeyVirtualKey != null) {
        HotkeyService().registerItemHotkey(result);
      }
    }
  });
}
