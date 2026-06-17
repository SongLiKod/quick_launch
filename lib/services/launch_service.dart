import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';
import 'launch_log_service.dart';
import 'item_service.dart';
import 'settings_service.dart';

/// 启动结果
typedef LaunchResult = ({bool success, String? errorMessage});

/// 运行中的进程信息
class ProcessInfo {
  final String itemName;
  final String targetPath;
  final Process process;
  final DateTime startTime;

  ProcessInfo({
    required this.itemName,
    required this.targetPath,
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

  final Map<String, ProcessInfo> _processes = {};
  final ValueNotifier<List<ProcessInfo>> runningProcesses =
      ValueNotifier([]);

  /// 启动一个项目，返回结果并记录日志
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
      switch (item.type) {
        case ItemType.executable:
        case ItemType.batScript:
          final process = await Process.start(
            item.targetPath,
            [],
            workingDirectory: _parentDir(item.targetPath),
          );
          _trackProcess(item.name, item.targetPath, process);
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

        case ItemType.command:
          await Process.run(
            'start',
            ['""', 'cmd', '/k', item.targetPath],
            runInShell: true,
          );
          break;

        case ItemType.link:
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

  void _trackProcess(String itemName, String targetPath, Process process) {
    final info = ProcessInfo(
      itemName: itemName,
      targetPath: targetPath,
      process: process,
      startTime: DateTime.now(),
    );
    _processes[itemName] = info;
    _notifyProcesses();

    // 进程退出时自动清理
    process.exitCode.then((_) {
      _processes.remove(itemName);
      _notifyProcesses();
    });
  }

  bool isRunning(String itemName) => _processes.containsKey(itemName);

  Future<bool> killProcess(String itemName) async {
    final info = _processes[itemName];
    if (info == null) return false;
    try {
      info.process.kill();
      // 等进程退出清理
      await info.process.exitCode;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> killAllProcesses() async {
    final names = _processes.keys.toList();
    for (final name in names) {
      try {
        _processes[name]?.process.kill();
      } catch (_) {
        // 忽略单个进程杀不掉的情况
      }
    }
    _processes.clear();
    _notifyProcesses();
  }

  List<String> get runningItemNames => _processes.keys.toList();

  void _notifyProcesses() {
    runningProcesses.value = _processes.values.toList();
  }

  String? _parentDir(String path) {
    try {
      return Directory(path).parent.path;
    } catch (_) {
      return null;
    }
  }
}
