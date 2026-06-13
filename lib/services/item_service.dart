import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/launch_item.dart';
import 'settings_service.dart';

class ItemService {
  static final ItemService _instance = ItemService._internal();
  factory ItemService() => _instance;
  ItemService._internal();

  static const String _storageKey = 'launch_items';

  final ValueNotifier<List<LaunchItem>> items = ValueNotifier([]);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return;

    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    final list = jsonList
        .map((e) => LaunchItem.fromJson(e as Map<String, dynamic>))
        .toList();
    items.value = list;
    applySort();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        json.encode(items.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<void> addItem(LaunchItem item) async {
    final list = [...items.value, item];
    items.value = list;
    await _save();
    applySort();
  }

  Future<void> removeItem(String id) async {
    final list = items.value.where((e) => e.id != id).toList();
    items.value = list;
    await _save();
  }

  Future<void> updateItem(LaunchItem item) async {
    final list = items.value.map((e) => e.id == item.id ? item : e).toList();
    items.value = list;
    await _save();
    applySort();
  }

  /// 拖拽排序 (配合 onReorderItem，newIndex 已自动调整)
  Future<void> reorderItem(int oldIndex, int newIndex) async {
    final list = items.value;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    items.value = list;
    await _save();
  }

  /// 按当前排序模式排序
  void applySort() {
    final mode = SettingsService().sortMode.value;
    if (mode == SortMode.manual) return;

    final list = List<LaunchItem>.from(items.value);
    if (mode == SortMode.name) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (mode == SortMode.created) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else if (mode == SortMode.type) {
      list.sort((a, b) => a.type.name.compareTo(b.type.name));
    }
    items.value = list;
  }

  /// 导出所有配置为 JSON 字符串
  String exportToJson() {
    return json.encode({
      'version': 1,
      'items': items.value.map((e) => e.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 从 JSON 字符串导入配置（追加，跳过重复 id）
  Future<int> importFromJson(String jsonStr) async {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final List<dynamic> jsonList = data['items'] as List<dynamic>;
    final imported = jsonList
        .map((e) => LaunchItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final existingIds = items.value.map((e) => e.id).toSet();
    final newItems = imported.where((e) => !existingIds.contains(e.id)).toList();

    if (newItems.isEmpty) return 0;

    items.value = [...items.value, ...newItems];
    await _save();
    applySort();
    return newItems.length;
  }

  /// 导出配置到文件
  Future<String> exportToFile() async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}\\quick_launch_backup.json');
    await file.writeAsString(exportToJson());
    return file.path;
  }

  /// 从文件导入配置
  Future<int> importFromFile(String filePath) async {
    final jsonStr = await File(filePath).readAsString();
    return importFromJson(jsonStr);
  }
}
