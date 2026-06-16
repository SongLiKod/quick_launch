import 'package:win32/win32.dart';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'launch_service.dart';
import 'item_service.dart';
import 'group_service.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  static const int baseHotkeyId = 100;
  static const int showWindowHotkeyId = 1;
  static const int searchHotkeyId = 2;
  static const int baseGroupHotkeyId = 5000;

  final Map<int, LaunchItem> _hotkeyMap = {};
  final Map<int, VoidCallback> _groupHotkeyCallbacks = {};

  int? _hWnd;

  // 显示窗口快捷键的回调
  VoidCallback? onShowWindow;

  // 搜索快捷键的回调
  VoidCallback? onSearchHotkey;

  // 分组快捷键回调，参数为 groupId
  void Function(String groupId)? onGroupHotkey;

  // 分组快捷键触发通知（HomePage 监听此 notifier 弹出选择覆盖层）
  final ValueNotifier<String?> groupHotkeyTrigger = ValueNotifier(null);

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

  /// 注册"搜索"全局快捷键
  void registerSearchHotkey(int modifiers, int virtualKey) {
    final result = RegisterHotKey(
      _ensureHWnd,
      searchHotkeyId,
      modifiers,
      virtualKey,
    );
    if (result == 0) {
      debugPrint('RegisterSearchHotKey failed, error: ${GetLastError()}');
    }
  }

  /// 注销"搜索"全局快捷键
  void unregisterSearchHotkey() {
    UnregisterHotKey(_ensureHWnd, searchHotkeyId);
  }

  /// 热键分发入口
  void onHotkeyPressed(int hotkeyId) {
    if (hotkeyId == showWindowHotkeyId) {
      onShowWindow?.call();
      return;
    }
    if (hotkeyId == searchHotkeyId) {
      onSearchHotkey?.call();
      return;
    }
    final item = _hotkeyMap[hotkeyId];
    if (item != null) {
      LaunchService().launch(item);
      return;
    }
    final groupCb = _groupHotkeyCallbacks[hotkeyId];
    if (groupCb != null) {
      groupCb();
      return;
    }
  }

  /// 注册分组快捷键
  void registerGroupHotkey(
      String groupId, int modifiers, int virtualKey) {
    final hotkeyId = baseGroupHotkeyId + (groupId.hashCode.abs() % 9000);
    _groupHotkeyCallbacks[hotkeyId] = () {
      onGroupHotkey?.call(groupId);
      groupHotkeyTrigger.value = groupId;
    };
    final result = RegisterHotKey(
      _ensureHWnd,
      hotkeyId,
      modifiers,
      virtualKey,
    );
    if (result == 0) {
      debugPrint(
          'RegisterGroupHotkey failed for $groupId, error: ${GetLastError()}');
    }
  }

  /// 注销分组快捷键
  void unregisterGroupHotkey(String groupId) {
    final hotkeyId = baseGroupHotkeyId + (groupId.hashCode.abs() % 9000);
    _groupHotkeyCallbacks.remove(hotkeyId);
    UnregisterHotKey(_ensureHWnd, hotkeyId);
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

  /// 检测分组快捷键是否冲突. 返回冲突分组的 name，无冲突返回 null.
  String? findGroupConflict(int? modifiers, int? virtualKey,
      {String? excludeGroupId}) {
    if (modifiers == null || virtualKey == null) return null;
    // 也要检查是否和单个项的快捷键冲突
    for (final item in ItemService().items.value) {
      if (item.hotkeyModifiers == modifiers &&
          item.hotkeyVirtualKey == virtualKey) {
        return item.name;
      }
    }
    // 检查其他分组
    for (final group in GroupService().groups.value) {
      if (excludeGroupId != null && group.id == excludeGroupId) continue;
      if (group.groupHotkeyModifiers == modifiers &&
          group.groupHotkeyVirtualKey == virtualKey) {
        return '分组: ${group.name}';
      }
    }
    return null;
  }

  void dispose() {
    if (_hWnd == null) return;
    UnregisterHotKey(_hWnd!, showWindowHotkeyId);
    UnregisterHotKey(_hWnd!, searchHotkeyId);
    for (final id in _hotkeyMap.keys) {
      UnregisterHotKey(_hWnd!, id);
    }
    _hotkeyMap.clear();
    for (final id in _groupHotkeyCallbacks.keys) {
      UnregisterHotKey(_hWnd!, id);
    }
    _groupHotkeyCallbacks.clear();
  }
}
