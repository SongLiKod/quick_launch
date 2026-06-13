import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/launch_item.dart';
import 'system_commands.dart';

class LaunchService {
  static final LaunchService _instance = LaunchService._internal();
  factory LaunchService() => _instance;
  LaunchService._internal();

  Future<void> launch(LaunchItem item) async {
    try {
      if (item.runAsAdmin) {
        await _launchAsAdmin(item);
        return;
      }

      switch (item.type) {
        case ItemType.executable:
        case ItemType.batScript:
          await Process.start(
            item.targetPath,
            [],
            runInShell: true,
            workingDirectory: _parentDir(item.targetPath),
          );
        case ItemType.file:
          await Process.start(
            'cmd',
            ['/c', 'start', '', item.targetPath],
            runInShell: true,
          );
        case ItemType.folder:
          await Process.start('explorer', [item.targetPath]);
        case ItemType.system:
          SystemCommands.execute(item.targetPath);
      }
    } catch (e) {
      debugPrint('Failed to launch ${item.name}: $e');
    }
  }

  Future<void> _launchAsAdmin(LaunchItem item) async {
    // ShellExecuteEx with "runas" verb requires win32
    // This falls back to normal start if admin is not available
    await Process.start(
      'powershell',
      ['Start-Process', item.targetPath, '-Verb', 'runAs'],
      runInShell: true,
    );
  }

  String? _parentDir(String path) {
    try {
      return Directory(path).parent.path;
    } catch (_) {
      return null;
    }
  }
}
