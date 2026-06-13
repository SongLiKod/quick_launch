import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';

/// 启动结果
typedef LaunchResult = ({bool success, String? errorMessage});

class LaunchService {
  static final LaunchService _instance = LaunchService._internal();
  factory LaunchService() => _instance;
  LaunchService._internal();

  /// 启动一个项目，返回结果（不抛出异常）
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
      switch (item.type) {
        case ItemType.executable:
          await Process.start(item.targetPath, [],
              runInShell: false,
              workingDirectory: _parentDir(item.targetPath));
          break;

        case ItemType.batScript:
          await Process.start('cmd.exe', ['/c', item.targetPath],
              runInShell: false,
              workingDirectory: _parentDir(item.targetPath));
          break;

        case ItemType.file:
          // 用系统关联程序打开
          await Process.run('cmd.exe', ['/c', 'start', '', item.targetPath],
              runInShell: false);
          break;

        case ItemType.folder:
          // 用资源管理器打开
          await Process.run('explorer.exe', [item.targetPath],
              runInShell: false);
          break;

        case ItemType.system:
          SystemCommands.execute(item.targetPath);
          break;
      }
      return (success: true, errorMessage: null);
    } catch (e) {
      debugPrint('Failed to launch ${item.name}: $e');
      return (success: false, errorMessage: e.toString());
    }
  }

  /// 安全获取父目录
  String? _parentDir(String path) {
    try {
      return Directory(path).parent.path;
    } catch (_) {
      return null;
    }
  }
}
