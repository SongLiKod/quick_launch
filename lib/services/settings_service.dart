import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 排序模式
enum SortMode { manual, name, created }

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  final ValueNotifier<bool> alwaysOnTop = ValueNotifier(false);
  final ValueNotifier<bool> minimizeToTray = ValueNotifier(true);
  final ValueNotifier<bool> autoStart = ValueNotifier(false);
  // 新增设置
  final ValueNotifier<bool> hideOnStartup = ValueNotifier(false);
  final ValueNotifier<int> startupDelay = ValueNotifier(0);
  final ValueNotifier<SortMode> sortMode = ValueNotifier(SortMode.manual);

  late SharedPreferences _prefs;

  static const _kThemeMode = 'theme_mode';
  static const _kAlwaysOnTop = 'always_on_top';
  static const _kMinimizeToTray = 'minimize_to_tray';
  static const _kAutoStart = 'auto_start';
  static const _kHideOnStartup = 'hide_on_startup';
  static const _kStartupDelay = 'startup_delay';
  static const _kSortMode = 'sort_mode';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    themeMode.value = _parseTheme(_prefs.getString(_kThemeMode));
    alwaysOnTop.value = _prefs.getBool(_kAlwaysOnTop) ?? false;
    minimizeToTray.value = _prefs.getBool(_kMinimizeToTray) ?? true;
    autoStart.value = _prefs.getBool(_kAutoStart) ?? false;
    hideOnStartup.value = _prefs.getBool(_kHideOnStartup) ?? false;
    startupDelay.value = _prefs.getInt(_kStartupDelay) ?? 0;
    sortMode.value = _parseSort(_prefs.getString(_kSortMode));
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
    _applyAutoStart(value, startupDelay.value);
  }

  Future<void> setHideOnStartup(bool value) async {
    hideOnStartup.value = value;
    await _prefs.setBool(_kHideOnStartup, value);
  }

  Future<void> setStartupDelay(int seconds) async {
    startupDelay.value = seconds;
    await _prefs.setInt(_kStartupDelay, seconds);
    // 如果开机自启已开启，更新注册表
    if (autoStart.value) {
      _applyAutoStart(true, seconds);
    }
  }

  Future<void> setSortMode(SortMode mode) async {
    sortMode.value = mode;
    await _prefs.setString(_kSortMode, _stringifySort(mode));
  }

  /// 写入/删除开机自启注册表，含延迟
  static void _applyAutoStart(bool enable, int delaySec) {
    final keyPath = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    final exePath = Platform.resolvedExecutable;
    if (enable) {
      // 有延迟则用 timeout 命令，无延迟直接启动
      final cmd = delaySec > 0
          ? 'cmd /c timeout /t $delaySec /nobreak >nul & start "" "$exePath"'
          : '"$exePath"';
      Process.run('reg', [
        'add', keyPath, '/v', 'QuickLaunch', '/t', 'REG_SZ', '/d', cmd, '/f',
      ]);
    } else {
      Process.run('reg', [
        'delete', keyPath, '/v', 'QuickLaunch', '/f',
      ]);
    }
  }

  static ThemeMode _parseTheme(String? s) {
    switch (s) {
      case 'dark': return ThemeMode.dark;
      case 'system': return ThemeMode.system;
      default: return ThemeMode.light;
    }
  }

  static String _stringifyTheme(ThemeMode mode) {
    if (mode == ThemeMode.dark) return 'dark';
    if (mode == ThemeMode.system) return 'system';
    return 'light';
  }

  static SortMode _parseSort(String? s) {
    switch (s) {
      case 'name': return SortMode.name;
      case 'created': return SortMode.created;
      default: return SortMode.manual;
    }
  }

  static String _stringifySort(SortMode mode) {
    switch (mode) {
      case SortMode.name: return 'name';
      case SortMode.created: return 'created';
      case SortMode.manual: return 'manual';
    }
  }
}
