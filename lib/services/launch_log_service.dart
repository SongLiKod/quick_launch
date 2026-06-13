import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动日志条目
class LaunchLogEntry {
  final DateTime timestamp;
  final String itemName;
  final String targetPath;
  final bool success;
  final String message;

  LaunchLogEntry({
    required this.timestamp,
    required this.itemName,
    required this.targetPath,
    required this.success,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'itemName': itemName,
        'targetPath': targetPath,
        'success': success,
        'message': message,
      };

  factory LaunchLogEntry.fromJson(Map<String, dynamic> json) => LaunchLogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        itemName: json['itemName'] as String,
        targetPath: json['targetPath'] as String,
        success: json['success'] as bool,
        message: json['message'] as String,
      );
}

class LaunchLogService {
  static final LaunchLogService _instance = LaunchLogService._internal();
  factory LaunchLogService() => _instance;
  LaunchLogService._internal();

  static const String _storageKey = 'launch_logs';
  static const int _maxLogs = 200;

  final ValueNotifier<List<LaunchLogEntry>> logs = ValueNotifier([]);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return;

    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    logs.value = jsonList
        .map((e) => LaunchLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(logs.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<void> addLog(LaunchLogEntry entry) async {
    final list = [entry, ...logs.value];
    if (list.length > _maxLogs) {
      list.removeRange(_maxLogs, list.length);
    }
    logs.value = list;
    await _save();
  }

  Future<void> clearLogs() async {
    logs.value = [];
    await _save();
  }
}
