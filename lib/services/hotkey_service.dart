import 'package:win32/win32.dart';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'launch_service.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  static const int baseHotkeyId = 100;

  final Map<int, LaunchItem> _hotkeyMap = {};

  int? _hWnd;

  void setWindowHandle(int hWnd) {
    _hWnd = hWnd;
  }

  int get _ensureHWnd {
    if (_hWnd == null) {
      throw StateError('Window handle not set. Call setWindowHandle first.');
    }
    return _hWnd!;
  }

  void registerItemHotkey(LaunchItem item) {
    if (item.hotkeyVirtualKey == null || item.hotkeyModifiers == null) return;

    final hotkeyId = baseHotkeyId + (item.id.hashCode.abs() % 9000);
    _hotkeyMap[hotkeyId] = item;

    final result = RegisterHotKey(
      _ensureHWnd,
      hotkeyId,
      item.hotkeyModifiers!,
      item.hotkeyVirtualKey!,
    );
    if (result == 0) {
      debugPrint(
          'RegisterHotKey failed for ${item.name}, error: ${GetLastError()}');
    }
  }

  /// 注销单个项目的快捷键
  void unregisterItemHotkey(LaunchItem item) {
    final hotkeyId = baseHotkeyId + (item.id.hashCode.abs() % 9000);
    _hotkeyMap.remove(hotkeyId);
    UnregisterHotKey(_ensureHWnd, hotkeyId);
  }

  void onHotkeyPressed(int hotkeyId) {
    final item = _hotkeyMap[hotkeyId];
    if (item != null) {
      LaunchService().launch(item);
    }
  }

  void dispose() {
    if (_hWnd == null) return;
    for (final id in _hotkeyMap.keys) {
      UnregisterHotKey(_hWnd!, id);
    }
    _hotkeyMap.clear();
  }
}
