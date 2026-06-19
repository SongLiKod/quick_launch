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
  final DateTime firstSeenAt;

  ProcessInfo({
    required this.itemName,
    required this.exeName,
    required this.pid,
    required this.firstSeenAt,
  });

  String get runningDurationText {
    final d = DateTime.now().difference(firstSeenAt);
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

  /// 当前正在运行的 exe 名集合（全小写），由 refreshRunningState() 更新
  final ValueNotifier<Set<String>> runningExeNames =
      ValueNotifier(<String>{});

  /// 刷新 runningExeNames：快速扫描 tasklist，返回当前系统上所有正在运行的 exe 名
  Future<void> refreshRunningState() async {
    try {
      final result = await Process.run('tasklist', ['/NH', '/FO', 'CSV']);
      final exes = <String>{};
      for (final line in result.stdout.toString().trim().split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(',');
        if (parts.isEmpty) continue;
        final imageName = parts[0].replaceAll('"', '').trim().toLowerCase();
        if (imageName.isNotEmpty) exes.add(imageName);
      }
      runningExeNames.value = exes;
    } catch (_) {
      // 失败时保留旧状态
    }
  }

  /// 从 targetPath 提取 exe 文件名（去掉路径和参数）
  /// "C:\Program Files\Chrome\chrome.exe" → "chrome.exe"
  /// "mysqld --console" → "mysqld"
  /// "notepad" → "notepad"
  String _exeName(String targetPath) {
    try {
      // 取文件名（最后一段）
      var name = targetPath.split(RegExp(r'[/\\]')).last;
      // 去掉参数（空格后的内容）
      name = name.split(RegExp(r'\s+')).first;
      if (name.isEmpty) return targetPath;
      return name;
    } catch (_) {
      return targetPath;
    }
  }

  /// 启动一个项目，返回结果并记录日志
  Future<LaunchResult> launch(LaunchItem item) async {
    try {
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

      // 延迟刷新运行状态（等进程真正启动）
      Future.delayed(const Duration(milliseconds: 500), refreshRunningState);

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
      return result.stdout.toString().contains(',');
    } catch (_) {
      return false;
    }
  }

  /// 结束指定进程（按 exe 名）
  Future<bool> killProcess(String exeName) async {
    if (exeName.isEmpty) return false;
    try {
      await Process.run('taskkill', ['/F', '/IM', exeName]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 扫描系统所有进程，与用户的所有启动项匹配，返回当前正在运行的进程列表
  Future<List<ProcessInfo>> scanRunningProcesses() async {
    // 从 ItemService 获取所有启动项，建立 exe名 -> 项名 映射
    final allItems = ItemService().items.value;
    final exeToItem = <String, String>{};
    for (final item in allItems) {
      final exe = _exeName(item.targetPath);
      if (exe.isNotEmpty) exeToItem[exe.toLowerCase()] = item.name;
    }
    if (exeToItem.isEmpty) return [];

    try {
      // 一次 tasklist 获取所有进程
      final result = await Process.run('tasklist', ['/NH', '/FO', 'CSV']);
      final running = <ProcessInfo>[];
      final seen = <String>{};

      for (final line in result.stdout.toString().trim().split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        final parts = trimmed.split(',');
        if (parts.length < 2) continue;

        final imageName = parts[0].replaceAll('"', '').trim().toLowerCase();
        if (imageName.isEmpty || seen.contains(imageName)) continue;

        final pidStr = parts[1].replaceAll('"', '').trim();
        final pid = int.tryParse(pidStr);
        if (pid == null || pid <= 0) continue;

        // 检查这个 exe 是否在用户启动项中
        final itemName = exeToItem[imageName] ?? exeToItem['$imageName.exe'];
        if (itemName == null) continue;

        seen.add(imageName);
        running.add(ProcessInfo(
          itemName: itemName,
          exeName: imageName,
          pid: pid,
          firstSeenAt: DateTime.now(),
        ));
      }

      return running;
    } catch (_) {
      return [];
    }
  }

  /// 退出时清理所有子进程（扫描 ItemService 中所有项）
  Future<void> killAllProcesses() async {
    final items = ItemService().items.value;
    final seen = <String>{};
    for (final item in items) {
      final exe = _exeName(item.targetPath);
      if (exe.isEmpty || seen.contains(exe.toLowerCase())) continue;
      seen.add(exe.toLowerCase());
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
