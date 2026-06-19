import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';
import 'launch_log_service.dart';
import 'item_service.dart';
import 'settings_service.dart';

/// 启动结果
typedef LaunchResult = ({bool success, String? errorMessage});

/// 正在追踪的进程信息（通过 Process.start 持有真实句柄）
class TrackedProcess {
  final String itemId;
  final String itemName;
  final Process process;
  final DateTime startTime;

  TrackedProcess({
    required this.itemId,
    required this.itemName,
    required this.process,
    required this.startTime,
  });

  int get pid => process.pid;

  Duration get runningDuration => DateTime.now().difference(startTime);

  String get runningDurationText {
    final d = runningDuration;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    } else {
      return '${d.inSeconds}s';
    }
  }
}

class LaunchService {
  static final LaunchService _instance = LaunchService._internal();
  factory LaunchService() => _instance;
  LaunchService._internal();

  /// 按 itemId 追踪的进程映射
  final Map<String, TrackedProcess> _tracked = {};

  /// 当前正在追踪的进程列表
  final ValueNotifier<List<TrackedProcess>> runningProcesses =
      ValueNotifier([]);

  /// 检查某个启动项是否正在运行
  bool isRunning(String itemId) => _tracked.containsKey(itemId);

  /// 将进程加入追踪（自动在进程退出时清理）
  void _track(LaunchItem item, Process process) {
    final tp = TrackedProcess(
      itemId: item.id,
      itemName: item.name,
      process: process,
      startTime: DateTime.now(),
    );
    _tracked[item.id] = tp;
    _notify();

    // 进程退出时自动清理
    process.exitCode.then((_) {
      _tracked.remove(item.id);
      _notify();
    });
  }

  void _notify() {
    runningProcesses.value = _tracked.values.toList();
  }

  /// 启动一个项目，返回结果并记录日志
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
      switch (item.type) {
        case ItemType.executable:
          // 直接启动 exe — GUI 应用会正常显示窗口
          final process = await Process.start(
            item.targetPath,
            [],
            workingDirectory: _parentDir(item.targetPath),
          );
          _track(item, process);
          break;

        case ItemType.batScript:
          // 通过 cmd /c 运行批处理
          final process = await Process.start(
            'cmd',
            ['/c', item.targetPath],
            workingDirectory: _parentDir(item.targetPath),
          );
          _track(item, process);
          break;

        case ItemType.command:
          // 通过 cmd /k 保持窗口打开
          final process = await Process.start(
            'cmd',
            ['/k', item.targetPath],
            workingDirectory: _parentDir(item.targetPath),
          );
          _track(item, process);
          break;

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

        case ItemType.link:
          await Process.run(
            'start',
            ['""', item.targetPath],
            runInShell: true,
            workingDirectory: _parentDir(item.targetPath),
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

      // 记录启动统计
      item.launchCount++;
      item.lastLaunchAt = DateTime.now();
      final sortMode = SettingsService().sortMode.value;
      if (sortMode == SortMode.mostUsed || sortMode == SortMode.recentlyUsed) {
        ItemService().applySort();
      } else {
        ItemService().notifyItemsChanged();
      }

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

  /// 按 itemId 杀进程
  Future<bool> killProcess(String itemId) async {
    final tp = _tracked[itemId];
    if (tp == null) return false;
    try {
      tp.process.kill();
      await tp.process.exitCode;
      // exitCode.then 回调中已清理 _tracked，这里确保通知
      _tracked.remove(itemId);
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 退出时清理所有子进程
  Future<void> killAllProcesses() async {
    final ids = _tracked.keys.toList();
    for (final id in ids) {
      try {
        _tracked[id]?.process.kill();
      } catch (_) {}
    }
    _tracked.clear();
    _notify();
  }

  String? _parentDir(String path) {
    try {
      return Directory(path).parent.path;
    } catch (_) {
      return null;
    }
  }
}
