import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
  final ValueNotifier<bool> alwaysOnTop = ValueNotifier(false);
  final ValueNotifier<bool> minimizeToTray = ValueNotifier(true);
  final ValueNotifier<bool> autoStart = ValueNotifier(false);

  late SharedPreferences _prefs;

  static const _kThemeMode = 'theme_mode';
  static const _kAlwaysOnTop = 'always_on_top';
  static const _kMinimizeToTray = 'minimize_to_tray';
  static const _kAutoStart = 'auto_start';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    themeMode.value = _parseTheme(_prefs.getString(_kThemeMode));
    alwaysOnTop.value = _prefs.getBool(_kAlwaysOnTop) ?? false;
    minimizeToTray.value = _prefs.getBool(_kMinimizeToTray) ?? true;
    autoStart.value = _prefs.getBool(_kAutoStart) ?? false;
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
    _applyAutoStart(value);
  }

  static void _applyAutoStart(bool enable) {
    final keyPath =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    final exePath = Platform.resolvedExecutable;
    if (enable) {
      Process.run('reg', [
        'add', keyPath, '/v', 'QuickLaunch', '/t', 'REG_SZ', '/d',
        '"$exePath"', '/f',
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
}
