import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// 当前版本号（从 pubspec.yaml version 字段读取）
  static const String currentVersion = '1.0.0';

  /// 最新版本号（从 GitHub 获取）
  String? latestVersion;

  /// 最新版本的下载链接
  String? downloadUrl;

  /// 是否已检查过更新（避免重复检查）
  bool _checked = false;

  /// 检查是否有新版本，返回 true 表示有新版本
  Future<bool> checkForUpdate() async {
    if (_checked && latestVersion != null) {
      return _isNewer(latestVersion!);
    }
    _checked = true;

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
        Uri.parse(
            'https://api.github.com/repos/qq1144403442/quick_launch/releases/latest'),
      );
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'quick_launch');

      final response = await request.close();
      if (response.statusCode != 200) return false;

      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;

      latestVersion = (data['tag_name'] as String).replaceFirst('v', '');
      downloadUrl = data['html_url'] as String?;

      client.close();
      return _isNewer(latestVersion!);
    } catch (_) {
      return false;
    }
  }

  /// 比较版本号
  bool _isNewer(String latest) {
    final currentParts = currentVersion.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final cur = i < currentParts.length ? currentParts[i] : 0;
      final lat = i < latestParts.length ? latestParts[i] : 0;
      if (lat > cur) return true;
      if (lat < cur) return false;
    }
    return false;
  }

  /// 显示更新提示对话框
  void showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本 🎉'),
        content: Text(
          '当前版本: v$currentVersion\n'
          '最新版本: v$latestVersion\n\n'
          '是否前往 GitHub 下载最新版本？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后提醒'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (downloadUrl != null) {
                Process.run('start', ['""', downloadUrl!], runInShell: true);
              }
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }
}
