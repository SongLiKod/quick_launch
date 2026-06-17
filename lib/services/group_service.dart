import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item_group.dart';
import 'item_service.dart';
import 'hotkey_service.dart';

class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  static const String _storageKey = 'item_groups';

  final ValueNotifier<List<ItemGroup>> groups = ValueNotifier([]);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return;

    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    groups.value = jsonList
        .map((e) => ItemGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        json.encode(groups.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<void> addGroup(ItemGroup group) async {
    final list = [...groups.value, group];
    groups.value = list;
    await _save();
    _registerGroupHotkey(group);
  }

  Future<void> updateGroup(ItemGroup group) async {
    // 如果快捷键变了，先注销旧的
    final old = groups.value.where((g) => g.id == group.id).firstOrNull;
    if (old != null && old.hasGroupHotkey) {
      HotkeyService().unregisterGroupHotkey(old.id);
    }
    final list =
        groups.value.map((e) => e.id == group.id ? group : e).toList();
    groups.value = list;
    await _save();
    _registerGroupHotkey(group);
  }

  Future<void> deleteGroup(String groupId) async {
    // 注销分组快捷键
    HotkeyService().unregisterGroupHotkey(groupId);

    // 将属于该分组的项移出分组
    final items = ItemService().items.value;
    for (int i = 0; i < items.length; i++) {
      if (items[i].groupId == groupId) {
        items[i].groupId = null;
      }
    }
    // 通知 ItemService 持久化
    ItemService().notifyItemsChanged();

    // 删除分组
    final list = groups.value.where((g) => g.id != groupId).toList();
    groups.value = list;
    await _save();
  }

  Future<void> moveItemToGroup(String itemId, String? groupId) async {
    final items = ItemService().items.value;
    for (int i = 0; i < items.length; i++) {
      if (items[i].id == itemId) {
        items[i].groupId = groupId;
        break;
      }
    }
    ItemService().notifyItemsChanged();
  }

  /// 批量移动启动项到指定分组
  Future<void> moveItemsToGroup(List<String> itemIds, String? groupId) async {
    final idSet = itemIds.toSet();
    final items = ItemService().items.value;
    for (int i = 0; i < items.length; i++) {
      if (idSet.contains(items[i].id)) {
        items[i].groupId = groupId;
      }
    }
    ItemService().notifyItemsChanged();
  }

  String? getGroupName(String? groupId) {
    if (groupId == null) return null;
    final idx = groups.value.indexWhere((g) => g.id == groupId);
    return idx >= 0 ? groups.value[idx].name : null;
  }

  void _registerGroupHotkey(ItemGroup group) {
    if (group.hasGroupHotkey) {
      HotkeyService().registerGroupHotkey(
          group.id, group.groupHotkeyModifiers!, group.groupHotkeyVirtualKey!);
    }
  }

  /// 从已加载的分组列表恢复所有分组快捷键（启动时调用）
  void loadAllGroupHotkeys() {
    for (final group in groups.value) {
      _registerGroupHotkey(group);
    }
  }

  static const List<int> presetColors = [
    0xFFE53935, // Red
    0xFFFF7043, // Deep Orange
    0xFFFFA726, // Orange
    0xFFFDD835, // Yellow
    0xFF66BB6A, // Green
    0xFF26A69A, // Teal
    0xFF42A5F5, // Blue
    0xFF5C6BC0, // Indigo
    0xFF7E57C2, // Deep Purple
    0xFFAB47BC, // Purple
    0xFFEC407A, // Pink
    0xFF8D6E63, // Brown
  ];
}
