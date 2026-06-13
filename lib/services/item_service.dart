import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/launch_item.dart';

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
  }
}
