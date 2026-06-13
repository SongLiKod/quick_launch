import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';
import 'launch_log_service.dart';

/// 启动结果
typedef LaunchResult = ({bool success, String? errorMessage});

class LaunchService {
  static final LaunchService _instance = LaunchService._internal();
  factory LaunchService() => _instance;
  LaunchService._internal();

  /// 启动一个项目，返回结果并记录日志
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
      switch (item.type) {
        case ItemType.executable:
        case ItemType.batScript:
        case ItemType.file:
          await Process.run(
            'start',
            ['""', item.targetPath],
            runInShell: true,
            workingDirectory: _parentDir(item.targetPath),
          );
          break;

        case ItemType.folder:
          await Process.run(
            'explorer.exe',
            [item.targetPath],
            runInShell: false,
          );
          break;

        case ItemType.system:
          SystemCommands.execute(item.targetPath);
          break;

        case ItemType.command:
          // 在新 CMD 窗口中运行命令，执行后保持窗口不关闭以便查看输出
          await Process.run(
            'start',
            ['""', 'cmd', '/k', item.targetPath],
            runInShell: true,
          );
          break;

        case ItemType.link:
          // 用默认浏览器打开链接
          await Process.run(
            'start',
            ['""', item.targetPath],
            runInShell: true,
          );
          break;
      }

      LaunchLogService().addLog(LaunchLogEntry(
        timestamp: DateTime.now(),
        itemName: item.name,
        targetPath: item.targetPath,
        success: true,
        message: '启动成功',
      ));

      return (success: true, errorMessage: null);
    } catch (e) {
      final msg = e.toString();

      LaunchLogService().addLog(LaunchLogEntry(
        timestamp: DateTime.now(),
        itemName: item.name,
        targetPath: item.targetPath,
        success: false,
        message: msg,
      ));

      debugPrint('Failed to launch ${item.name}: $msg');
      return (success: false, errorMessage: msg);
    }
  }

  String? _parentDir(String path) {
    try {
      return Directory(path).parent.path;
    } catch (_) {
      return null;
    }
  }
}
