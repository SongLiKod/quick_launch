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
  static const int togglePauseHotkeyId = 9999;

  final Map<int, LaunchItem> _hotkeyMap = {};
  final Map<int, VoidCallback> _groupHotkeyCallbacks = {};

  int? _hWnd;
  int? _savedShowWindowModifiers;
  int? _savedShowWindowKey;
  int? _savedSearchModifiers;
  int? _savedSearchKey;
  int? _savedPauseModifiers;
  int? _savedPauseKey;

  // 显示窗口快捷键的回调
  VoidCallback? onShowWindow;

  // 搜索快捷键的回调
  VoidCallback? onSearchHotkey;

  // 分组快捷键回调，参数为 groupId
  void Function(String groupId)? onGroupHotkey;

  // 热键暂停状态切换回调（托盘菜单刷新用）
  VoidCallback? onPauseToggled;

  // 分组快捷键触发通知（HomePage 监听此 notifier 弹出选择覆盖层）
  final ValueNotifier<String?> groupHotkeyTrigger = ValueNotifier(null);

  // 暂停状态
  final ValueNotifier<bool> paused = ValueNotifier(false);

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
    if (paused.value) return;

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
        'RegisterHotKey failed for ${item.name}, error: ${GetLastError()}',
      );
    }
  }

  void unregisterItemHotkey(LaunchItem item) {
    final hotkeyId = baseHotkeyId + (item.id.hashCode.abs() % 9000);
    _hotkeyMap.remove(hotkeyId);
    if (!paused.value) {
      UnregisterHotKey(_ensureHWnd, hotkeyId);
    }
  }

  /// 注册"显示窗口"全局快捷键
  void registerShowWindowHotkey(int modifiers, int virtualKey) {
    _savedShowWindowModifiers = modifiers;
    _savedShowWindowKey = virtualKey;
    if (paused.value) return;
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
    _savedShowWindowModifiers = null;
    _savedShowWindowKey = null;
    if (!paused.value) {
      UnregisterHotKey(_ensureHWnd, showWindowHotkeyId);
    }
  }

  /// 注册"搜索"全局快捷键
  void registerSearchHotkey(int modifiers, int virtualKey) {
    _savedSearchModifiers = modifiers;
    _savedSearchKey = virtualKey;
    if (paused.value) return;
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
    _savedSearchModifiers = null;
    _savedSearchKey = null;
    if (!paused.value) {
      UnregisterHotKey(_ensureHWnd, searchHotkeyId);
    }
  }

  /// 注册暂停切换快捷键（可配置）
  void registerPauseHotkey(int modifiers, int virtualKey) {
    _savedPauseModifiers = modifiers;
    _savedPauseKey = virtualKey;
    if (paused.value) return;
    RegisterHotKey(_ensureHWnd, togglePauseHotkeyId, modifiers, virtualKey);
  }

  /// 注销暂停切换快捷键
  void unregisterPauseHotkey() {
    _savedPauseModifiers = null;
    _savedPauseKey = null;
    if (!paused.value) {
      UnregisterHotKey(_ensureHWnd, togglePauseHotkeyId);
    }
  }

  /// 热键分发入口
  void onHotkeyPressed(int hotkeyId) {
    try {
      // 暂停切换快捷键始终响应
      if (hotkeyId == togglePauseHotkeyId) {
        togglePause();
        return;
      }
      // 暂停状态下不响应其他任何热键
      if (paused.value) return;

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
    } catch (e) {
      debugPrint('onHotkeyPressed error: $e');
    }
  }

  /// 注册分组快捷键
  void registerGroupHotkey(String groupId, int modifiers, int virtualKey) {
    final hotkeyId = baseGroupHotkeyId + (groupId.hashCode.abs() % 9000);
    _groupHotkeyCallbacks[hotkeyId] = () {
      onGroupHotkey?.call(groupId);
      groupHotkeyTrigger.value = groupId;
    };
    if (paused.value) return;
    final result = RegisterHotKey(_ensureHWnd, hotkeyId, modifiers, virtualKey);
    if (result == 0) {
      debugPrint(
        'RegisterGroupHotkey failed for $groupId, error: ${GetLastError()}',
      );
    }
  }

  /// 注销分组快捷键
  void unregisterGroupHotkey(String groupId) {
    final hotkeyId = baseGroupHotkeyId + (groupId.hashCode.abs() % 9000);
    _groupHotkeyCallbacks.remove(hotkeyId);
    if (!paused.value) {
      UnregisterHotKey(_ensureHWnd, hotkeyId);
    }
  }

  /// 暂停所有热键（保留注册信息以便恢复）
  void pauseAll() {
    if (paused.value || _hWnd == null) return;
    // 注销暂停切换、系统热键
    UnregisterHotKey(_hWnd!, togglePauseHotkeyId);
    UnregisterHotKey(_hWnd!, showWindowHotkeyId);
    UnregisterHotKey(_hWnd!, searchHotkeyId);
    // 注销单项热键
    for (final id in _hotkeyMap.keys) {
      UnregisterHotKey(_hWnd!, id);
    }
    // 注销分组热键
    for (final id in _groupHotkeyCallbacks.keys) {
      UnregisterHotKey(_hWnd!, id);
    }
    paused.value = true;
    onPauseToggled?.call();
  }

  /// 恢复所有热键
  void resumeAll() {
    if (!paused.value || _hWnd == null) return;
    // 恢复暂停切换热键
    if (_savedPauseModifiers != null && _savedPauseKey != null) {
      RegisterHotKey(
        _hWnd!,
        togglePauseHotkeyId,
        _savedPauseModifiers!,
        _savedPauseKey!,
      );
    }
    // 恢复显示窗口热键
    if (_savedShowWindowModifiers != null && _savedShowWindowKey != null) {
      RegisterHotKey(
        _hWnd!,
        showWindowHotkeyId,
        _savedShowWindowModifiers!,
        _savedShowWindowKey!,
      );
    }
    // 恢复搜索热键
    if (_savedSearchModifiers != null && _savedSearchKey != null) {
      RegisterHotKey(
        _hWnd!,
        searchHotkeyId,
        _savedSearchModifiers!,
        _savedSearchKey!,
      );
    }
    // 恢复单项热键
    for (final entry in _hotkeyMap.entries) {
      final item = entry.value;
      if (item.hotkeyModifiers != null && item.hotkeyVirtualKey != null) {
        RegisterHotKey(
          _hWnd!,
          entry.key,
          item.hotkeyModifiers!,
          item.hotkeyVirtualKey!,
        );
      }
    }
    // 恢复分组热键（ID 从 _groupHotkeyCallbacks 重构）
    // 分组热键信息不在 map 中，需要从 GroupService 重新获取
    for (final group in GroupService().groups.value) {
      if (group.groupHotkeyModifiers != null &&
          group.groupHotkeyVirtualKey != null) {
        final hotkeyId = baseGroupHotkeyId + (group.id.hashCode.abs() % 9000);
        RegisterHotKey(
          _hWnd!,
          hotkeyId,
          group.groupHotkeyModifiers!,
          group.groupHotkeyVirtualKey!,
        );
      }
    }
    paused.value = false;
    onPauseToggled?.call();
  }

  /// 切换暂停状态
  void togglePause() {
    if (paused.value) {
      resumeAll();
    } else {
      pauseAll();
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

  /// 检测分组快捷键是否冲突. 返回冲突分组的 name，无冲突返回 null.
  String? findGroupConflict(
    int? modifiers,
    int? virtualKey, {
    String? excludeGroupId,
  }) {
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
    if (_savedPauseModifiers != null && _savedPauseKey != null) {
      UnregisterHotKey(_hWnd!, togglePauseHotkeyId);
    }
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
