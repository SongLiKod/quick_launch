import 'package:win32/win32.dart';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'launch_service.dart';
import 'item_service.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  static const int baseHotkeyId = 100;
  static const int showWindowHotkeyId = 1;

  final Map<int, LaunchItem> _hotkeyMap = {};

  int? _hWnd;

  // 显示窗口快捷键的回调
  VoidCallback? onShowWindow;

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

  void unregisterItemHotkey(LaunchItem item) {
    final hotkeyId = baseHotkeyId + (item.id.hashCode.abs() % 9000);
    _hotkeyMap.remove(hotkeyId);
    UnregisterHotKey(_ensureHWnd, hotkeyId);
  }

  /// 注册"显示窗口"全局快捷键
  void registerShowWindowHotkey(int modifiers, int virtualKey) {
    final result = RegisterHotKey(
      _ensureHWnd,
      showWindowHotkeyId,
      modifiers,
      virtualKey,
    );
    if (result == 0) {
      debugPrint('RegisterShowWindowHotKey failed, error: ${GetLastError()}');
    }
  }

  /// 注销"显示窗口"全局快捷键
  void unregisterShowWindowHotkey() {
    UnregisterHotKey(_ensureHWnd, showWindowHotkeyId);
  }

  /// 热键分发入口
  void onHotkeyPressed(int hotkeyId) {
    if (hotkeyId == showWindowHotkeyId) {
      onShowWindow?.call();
      return;
    }
    final item = _hotkeyMap[hotkeyId];
    if (item != null) {
      LaunchService().launch(item);
    }
  }

  /// 检测快捷键是否冲突. 返回冲突项的 name，无冲突返回 null.
  String? findConflict(int? modifiers, int? virtualKey, {String? excludeId}) {
    if (modifiers == null || virtualKey == null) return null;
    for (final item in ItemService().items.value) {
      if (excludeId != null && item.id == excludeId) continue;
      if (item.hotkeyModifiers == modifiers &&
          item.hotkeyVirtualKey == virtualKey) {
        return item.name;
      }
    }
    return null;
  }

  void dispose() {
    if (_hWnd == null) return;
    UnregisterHotKey(_hWnd!, showWindowHotkeyId);
    for (final id in _hotkeyMap.keys) {
      UnregisterHotKey(_hWnd!, id);
    }
    _hotkeyMap.clear();
  }
}
