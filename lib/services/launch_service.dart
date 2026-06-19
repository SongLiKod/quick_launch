import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';
import 'launch_log_service.dart';
import 'item_service.dart';
import 'settings_service.dart';

/// 启动结果
typedef LaunchResult = ({bool success, String? errorMessage});

/// 进程信息（通过 tasklist 扫描获得）
class ProcessInfo {
  final String itemName;
  final String exeName;
  final int pid;
  final DateTime startTime;

  ProcessInfo({
    required this.itemName,
    required this.exeName,
    required this.pid,
    required this.startTime,
  });

  String get runningDurationText {
    final d = DateTime.now().difference(startTime);
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

  /// 已启动项列表 — 记录用户通过本应用启动过的项目
  final List<({String itemName, String targetPath, DateTime launchedAt})>
      _launchedItems = [];

  /// 从 targetPath 提取 exe 文件名
  String _exeName(String targetPath) {
    try {
      final name = targetPath.split(RegExp(r'[/\\]')).last;
      return name;
    } catch (_) {
      return targetPath;
    }
  }

  /// 启动一个项目，返回结果并记录日志
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
      // 记录已启动（用于结束后台进程和退出清理）
      _launchedItems.add((
        itemName: item.name,
        targetPath: item.targetPath,
        launchedAt: DateTime.now(),
      ));

      switch (item.type) {
        case ItemType.executable:
        case ItemType.batScript:
          await Process.run(
            'start',
            ['""', item.targetPath],
            runInShell: true,
            workingDirectory: _parentDir(item.targetPath),
          );
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

  /// 查指定 exe 是否在运行
  Future<bool> isRunning(String targetPath) async {
    final exe = _exeName(targetPath);
    if (exe.isEmpty) return false;
    try {
      final result = await Process.run(
        'tasklist',
        ['/NH', '/FO', 'CSV', '/FI', 'IMAGENAME eq $exe'],
      );
      // tasklist 输出: "xxx.exe","pid","...", 无匹配时只有标题行
      return result.stdout.toString().contains(',');
    } catch (_) {
      return false;
    }
  }

  /// 结束指定进程
  Future<bool> killProcess(String targetPath) async {
    final exe = _exeName(targetPath);
    if (exe.isEmpty) return false;
    try {
      await Process.run('taskkill', ['/F', '/IM', exe]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 扫描所有已启动项，返回当前正在运行的进程列表
  Future<List<ProcessInfo>> scanRunningProcesses() async {
    final results = <ProcessInfo>[];
    final seen = <String>{};

    for (final launched in _launchedItems) {
      final exe = _exeName(launched.targetPath);
      if (exe.isEmpty || seen.contains(exe)) continue;
      seen.add(exe);

      try {
        final result = await Process.run(
          'tasklist',
          ['/NH', '/FO', 'CSV', '/FI', 'IMAGENAME eq $exe'],
        );
        final lines = result.stdout.toString().trim().split('\n');
        for (final line in lines) {
          // CSV 格式: "exe.exe","pid","session","session#","mem"
          final parts = line.split(',');
          if (parts.length >= 2) {
            final pidStr = parts[1].replaceAll('"', '').trim();
            final pid = int.tryParse(pidStr);
            if (pid != null && pid > 0) {
              results.add(ProcessInfo(
                itemName: launched.itemName,
                exeName: exe,
                pid: pid,
                startTime: launched.launchedAt,
              ));
              break; // 一个 exe 只取一条
            }
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// 退出时清理所有已启动的子进程
  Future<void> killAllProcesses() async {
    final seen = <String>{};
    for (final launched in _launchedItems) {
      final exe = _exeName(launched.targetPath);
      if (exe.isEmpty || seen.contains(exe)) continue;
      seen.add(exe);
      try {
        await Process.run('taskkill', ['/F', '/IM', exe]);
      } catch (_) {}
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
