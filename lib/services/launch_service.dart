import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';
import 'launch_log_service.dart';
import 'item_service.dart';
import 'settings_service.dart';

/// 启动结果
typedef LaunchResult = ({bool success, String? errorMessage});

class LaunchService {
  static final LaunchService _instance = LaunchService._internal();
  factory LaunchService() => _instance;
  LaunchService._internal();

  static const _settingsChannel = MethodChannel('quick_launch/settings');

  /// 启动一个项目，返回结果并记录日志
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
      // 管理员提权启动
      if (item.runAsAdmin) {
        switch (item.type) {
          case ItemType.executable:
          case ItemType.batScript:
          case ItemType.file:
          case ItemType.folder:
          case ItemType.link:
            final ok = await _launchAsAdmin(item.targetPath);
            if (!ok) {
              return (success: false, errorMessage: '提权启动失败，可能被用户取消');
            }
            break;
          case ItemType.system:
            // 系统命令不适用提权，降级为普通启动
            SystemCommands.execute(item.targetPath);
            break;
          case ItemType.command:
            // 命令类型暂不支持提权，降级为普通启动
            await Process.run(
              'start',
              ['""', 'cmd', '/k', item.targetPath],
              runInShell: true,
            );
            break;
        }

        _recordSuccess(item);
        return (success: true, errorMessage: null);
      }

      // 普通启动
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

      _recordSuccess(item);
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

  Future<bool> _launchAsAdmin(String path) async {
    try {
      final ok = await _settingsChannel.invokeMethod<bool>('runAsAdmin', path);
      return ok ?? false;
    } catch (e) {
      debugPrint('runAsAdmin failed: $e');
      return false;
    }
  }

  void _recordSuccess(LaunchItem item) {
    LaunchLogService().addLog(LaunchLogEntry(
      timestamp: DateTime.now(),
      itemName: item.name,
      targetPath: item.targetPath,
      success: true,
      message: '启动成功',
    ));

    // 记录启动统计
    item.launchCount++;
    item.lastLaunchAt = DateTime.now();
    final sortMode = SettingsService().sortMode.value;
    if (sortMode == SortMode.mostUsed || sortMode == SortMode.recentlyUsed) {
      ItemService().applySort();
    } else {
      ItemService().notifyItemsChanged();
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
