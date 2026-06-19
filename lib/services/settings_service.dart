import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 排序模式
enum SortMode { manual, name, created, type, mostUsed, recentlyUsed }

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  final ValueNotifier<bool> alwaysOnTop = ValueNotifier(false);
  final ValueNotifier<bool> minimizeToTray = ValueNotifier(true);
  final ValueNotifier<bool> autoStart = ValueNotifier(false);
  final ValueNotifier<bool> hideOnStartup = ValueNotifier(false);
  final ValueNotifier<int> startupDelay = ValueNotifier(0);
  final ValueNotifier<SortMode> sortMode = ValueNotifier(SortMode.manual);
  // 显示窗口快捷键
  final ValueNotifier<int?> showWindowModifiers = ValueNotifier(null);
  final ValueNotifier<int?> showWindowKey = ValueNotifier(null);
  // 搜索快捷键
  final ValueNotifier<int?> searchHotkeyModifiers = ValueNotifier(null);
  final ValueNotifier<int?> searchHotkeyKey = ValueNotifier(null);
  // 自定义图标路径
  final ValueNotifier<String?> customIconPath = ValueNotifier(null);
  // 多列展示
  final ValueNotifier<int> columnCount = ValueNotifier(1);
  // 右键菜单
  final ValueNotifier<bool> contextMenuEnabled = ValueNotifier(false);

  late SharedPreferences _prefs;

  static const _kThemeMode = 'theme_mode';
  static const _kAlwaysOnTop = 'always_on_top';
  static const _kMinimizeToTray = 'minimize_to_tray';
  static const _kAutoStart = 'auto_start';
  static const _kHideOnStartup = 'hide_on_startup';
  static const _kStartupDelay = 'startup_delay';
  static const _kSortMode = 'sort_mode';
  static const _kShowWindowModifiers = 'show_window_modifiers';
  static const _kShowWindowKey = 'show_window_key';
  static const _kSearchHotkeyModifiers = 'search_hotkey_modifiers';
  static const _kSearchHotkeyKey = 'search_hotkey_key';
  static const _kCustomIconPath = 'custom_icon_path';
  static const _kColumnCount = 'column_count';
  static const _kContextMenu = 'context_menu_enabled';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    themeMode.value = _parseTheme(_prefs.getString(_kThemeMode));
    alwaysOnTop.value = _prefs.getBool(_kAlwaysOnTop) ?? false;
    minimizeToTray.value = _prefs.getBool(_kMinimizeToTray) ?? true;
    autoStart.value = _prefs.getBool(_kAutoStart) ?? false;
    hideOnStartup.value = _prefs.getBool(_kHideOnStartup) ?? false;
    startupDelay.value = _prefs.getInt(_kStartupDelay) ?? 0;
    sortMode.value = _parseSort(_prefs.getString(_kSortMode));
    // 注意：int? 存储为 int，默认 -1 表示 null
    final swm = _prefs.getInt(_kShowWindowModifiers);
    showWindowModifiers.value = (swm != null && swm >= 0) ? swm : null;
    final swk = _prefs.getInt(_kShowWindowKey);
    showWindowKey.value = (swk != null && swk >= 0) ? swk : null;
    final shm = _prefs.getInt(_kSearchHotkeyModifiers);
    searchHotkeyModifiers.value = (shm != null && shm >= 0) ? shm : null;
    final shk = _prefs.getInt(_kSearchHotkeyKey);
    searchHotkeyKey.value = (shk != null && shk >= 0) ? shk : null;
    customIconPath.value = _prefs.getString(_kCustomIconPath);
    columnCount.value = _prefs.getInt(_kColumnCount) ?? 1;
    contextMenuEnabled.value = _prefs.getBool(_kContextMenu) ?? false;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _prefs.setString(_kThemeMode, _stringifyTheme(mode));
  }

  Future<void> setAlwaysOnTop(bool value) async {
    alwaysOnTop.value = value;
    await _prefs.setBool(_kAlwaysOnTop, value);
  }

  Future<void> setMinimizeToTray(bool value) async {
    minimizeToTray.value = value;
    await _prefs.setBool(_kMinimizeToTray, value);
  }

  Future<void> setAutoStart(bool value) async {
    autoStart.value = value;
    await _prefs.setBool(_kAutoStart, value);
    await _applyAutoStart(value, startupDelay.value);
  }

  Future<void> setHideOnStartup(bool value) async {
    hideOnStartup.value = value;
    await _prefs.setBool(_kHideOnStartup, value);
  }

  Future<void> setStartupDelay(int seconds) async {
    startupDelay.value = seconds;
    await _prefs.setInt(_kStartupDelay, seconds);
    if (autoStart.value) {
      await _applyAutoStart(true, seconds);
    }
  }

  Future<void> setSortMode(SortMode mode) async {
    sortMode.value = mode;
    await _prefs.setString(_kSortMode, _stringifySort(mode));
  }

  Future<void> setShowWindowHotkey(int? modifiers, int? key) async {
    showWindowModifiers.value = modifiers;
    showWindowKey.value = key;
    await _prefs.setInt(_kShowWindowModifiers, modifiers ?? -1);
    await _prefs.setInt(_kShowWindowKey, key ?? -1);
  }

  Future<void> setSearchHotkey(int? modifiers, int? key) async {
    // 先设 key 再设 modifiers — 确保监听 searchHotkeyModifiers 时 key 已就绪
    searchHotkeyKey.value = key;
    searchHotkeyModifiers.value = modifiers;
    await _prefs.setInt(_kSearchHotkeyModifiers, modifiers ?? -1);
    await _prefs.setInt(_kSearchHotkeyKey, key ?? -1);
  }

  Future<void> setCustomIconPath(String? path) async {
    // 不保存空路径，避免启动时 File() 构造异常
    if (path != null && path.trim().isEmpty) path = null;
    customIconPath.value = path;
    if (path != null) {
      await _prefs.setString(_kCustomIconPath, path);
    } else {
      await _prefs.remove(_kCustomIconPath);
    }
  }

  Future<void> setColumnCount(int value) async {
    final clamped = value.clamp(1, 4);
    columnCount.value = clamped;
    await _prefs.setInt(_kColumnCount, clamped);
  }

  Future<void> setContextMenuEnabled(bool enable) async {
    contextMenuEnabled.value = enable;
    await _prefs.setBool(_kContextMenu, enable);
    if (enable) {
      await _installContextMenu();
    } else {
      await _uninstallContextMenu();
    }
  }

  /// 安装右键菜单：写入注册表 + 创建 SendTo 快捷方式
  static Future<void> _installContextMenu() async {
    final exePath = Platform.resolvedExecutable;

    // 写入 HKCU\Software\Classes（当前用户，无需管理员权限）
    // 1. 注册表：* → 所有文件
    await _regAdd(r'HKCU\Software\Classes\*\shell\QuickLaunch', '添加到快速启动');
    await _regAdd(
      r'HKCU\Software\Classes\*\shell\QuickLaunch\command',
      '"$exePath" "--add-file" "%1"',
    );

    // 2. 注册表：Directory → 文件夹
    await _regAdd(
      r'HKCU\Software\Classes\Directory\shell\QuickLaunch',
      '添加到快速启动',
    );
    await _regAdd(
      r'HKCU\Software\Classes\Directory\shell\QuickLaunch\command',
      '"$exePath" "--add-file" "%1"',
    );

    // 3. 注册表：Directory\Background → 文件夹背景空白处
    await _regAdd(
      r'HKCU\Software\Classes\Directory\Background\shell\QuickLaunch',
      '添加到快速启动',
    );
    await _regAdd(
      r'HKCU\Software\Classes\Directory\Background\shell\QuickLaunch\command',
      '"$exePath" "--add-file" "%V"',
    );

    // 4. SendTo 快捷方式
    final sendTo =
        Platform.environment['APPDATA']! +
        r'\Microsoft\Windows\SendTo\Quick Launch.lnk';
    await _createShortcut(exePath, '--add-file', sendTo);
  }

  /// 卸载右键菜单：清理注册表 + 删除 SendTo 快捷方式
  static Future<void> _uninstallContextMenu() async {
    await _regDelete(r'HKCU\Software\Classes\*\shell\QuickLaunch');
    await _regDelete(r'HKCU\Software\Classes\Directory\shell\QuickLaunch');
    await _regDelete(
      r'HKCU\Software\Classes\Directory\Background\shell\QuickLaunch',
    );

    // 删除 SendTo 快捷方式
    final sendTo =
        Platform.environment['APPDATA']! +
        r'\Microsoft\Windows\SendTo\Quick Launch.lnk';
    final file = File(sendTo);
    if (await file.exists()) await file.delete();
  }

  static Future<void> _regAdd(String keyPath, String value) async {
    await Process.run('reg', ['add', keyPath, '/ve', '/d', value, '/f']);
  }

  static Future<void> _regDelete(String keyPath) async {
    await Process.run('reg', ['delete', keyPath, '/f']);
  }

  /// 使用 PowerShell 创建 .lnk 快捷方式
  static Future<void> _createShortcut(
    String target,
    String args,
    String destPath,
  ) async {
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'$ws = New-Object -ComObject WScript.Shell;'
          r'$s = $ws.CreateShortcut('
          "$destPath"
          ');'
          r'$s.TargetPath = '
          "$target"
          ';'
          r'$s.Arguments = '
          "$args"
          ';'
          r'$s.Save()',
    ]);
  }

  /// 写入/删除开机自启注册表，含延迟
  static Future<void> _applyAutoStart(bool enable, int delaySec) async {
    final keyPath = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    final exePath = Platform.resolvedExecutable;
    try {
      if (enable) {
        // 无延迟：直接写 exe 路径，用引号包裹防止空格问题
        // 有延迟：用 cmd /c timeout 实现延时启动
        final cmd = delaySec > 0
            ? 'cmd /c timeout /t $delaySec /nobreak >nul & start "" "$exePath"'
            : '"$exePath"';
        final result = await Process.run('reg', [
          'add',
          keyPath,
          '/v',
          'QuickLaunch',
          '/t',
          'REG_SZ',
          '/d',
          cmd,
          '/f',
          '/reg:64',
        ]);
        if (result.exitCode != 0) {
          // ignore: avoid_print
          print('注册开机自启失败: ${result.stderr}');
        }
      } else {
        await Process.run('reg', [
          'delete',
          keyPath,
          '/v',
          'QuickLaunch',
          '/f',
        ]);
      }
    } catch (e) {
      // ignore: avoid_print
      print('注册开机自启异常: $e');
    }
  }

  static ThemeMode _parseTheme(String? s) {
    switch (s) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  static String _stringifyTheme(ThemeMode mode) {
    if (mode == ThemeMode.dark) return 'dark';
    if (mode == ThemeMode.system) return 'system';
    return 'light';
  }

  static SortMode _parseSort(String? s) {
    switch (s) {
      case 'name':
        return SortMode.name;
      case 'created':
        return SortMode.created;
      case 'type':
        return SortMode.type;
      case 'mostUsed':
        return SortMode.mostUsed;
      case 'recentlyUsed':
        return SortMode.recentlyUsed;
      default:
        return SortMode.manual;
    }
  }

  static String _stringifySort(SortMode mode) {
    switch (mode) {
      case SortMode.name:
        return 'name';
      case SortMode.created:
        return 'created';
      case SortMode.type:
        return 'type';
      case SortMode.mostUsed:
        return 'mostUsed';
      case SortMode.recentlyUsed:
        return 'recentlyUsed';
      case SortMode.manual:
        return 'manual';
    }
  }
}
