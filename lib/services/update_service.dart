import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 更新流程阶段
enum UpdatePhase {
  /// 未检查
  idle,

  /// 正在检查
  checking,

  /// 已是最新版本
  upToDate,

  /// 发现新版本
  available,

  /// 正在下载安装包
  downloading,

  /// 正在准备安装
  installing,

  /// 检查失败
  checkFailed,

  /// 安装失败
  installFailed,
}

/// 更新状态（供主界面底部横幅与设置页监听）
class UpdateState {
  final UpdatePhase phase;

  /// 最新版本号
  final String? latestVersion;

  /// 下载进度 0~1（contentLength 未知时为 -1）
  final double progress;

  /// 失败原因
  final String? error;

  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.latestVersion,
    this.progress = 0,
    this.error,
  });
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// 当前版本号（编译时从 pubspec.yaml 注入，无注入时 fallback）
  static const String currentVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  static const _repoApi =
      'https://api.github.com/repos/qq1144403442/quick_launch/releases/latest';
  static const _exeName = 'quick_launch.exe';
  static const _zipName = 'quick_launch_windows.zip';

  final ValueNotifier<UpdateState> state = ValueNotifier(const UpdateState());

  String? _zipUrl;

  /// 检查是否有新版本，返回 true 表示有新版本
  ///
  /// [force] 为 true 时忽略缓存重新检查（设置页手动检查）；
  /// 检查失败会写入 [UpdatePhase.checkFailed] 状态。
  Future<bool> checkForUpdate({bool force = false}) async {
    final current = state.value;
    if (current.phase == UpdatePhase.downloading ||
        current.phase == UpdatePhase.installing) {
      return false;
    }
    if (!force &&
        (current.phase == UpdatePhase.checking ||
            current.phase == UpdatePhase.available)) {
      return current.phase == UpdatePhase.available;
    }

    state.value = UpdateState(
      phase: UpdatePhase.checking,
      latestVersion: current.latestVersion,
    );

    try {
      final data = await _fetchLatestRelease();
      final latest =
          ((data['tag_name'] as String?) ?? '').replaceFirst(RegExp('^v'), '');
      if (latest.isEmpty) throw Exception('未获取到版本号');
      _zipUrl = _findZipUrl(data);

      final hasUpdate = _isNewer(latest);
      state.value = UpdateState(
        phase: hasUpdate ? UpdatePhase.available : UpdatePhase.upToDate,
        latestVersion: latest,
      );
      return hasUpdate;
    } catch (e) {
      state.value = UpdateState(
        phase: UpdatePhase.checkFailed,
        error: e.toString(),
      );
      return false;
    }
  }

  /// 下载最新版本并在界面内完成安装：
  /// 下载 zip → 解压 → 生成升级脚本 → 退出应用，由脚本替换文件并重启
  Future<void> downloadAndInstall() async {
    final zip = _zipUrl;
    final latest = state.value.latestVersion;
    if (zip == null || latest == null) {
      _fail(true, '未找到安装包下载地址，请稍后重试');
      return;
    }
    if (state.value.phase == UpdatePhase.downloading ||
        state.value.phase == UpdatePhase.installing) {
      return;
    }

    try {
      state.value = UpdateState(
        phase: UpdatePhase.downloading,
        latestVersion: latest,
      );

      final workDir =
          await Directory.systemTemp.createTemp('quick_launch_update_');
      final zipFile = File('${workDir.path}\\$_zipName');
      await _download(zip, zipFile);

      state.value = UpdateState(
        phase: UpdatePhase.installing,
        latestVersion: latest,
        progress: 1,
      );

      final extractDir = Directory('${workDir.path}\\extracted');
      await extractDir.create(recursive: true);
      await _extract(zipFile, extractDir);

      final newExe = File('${extractDir.path}\\$_exeName');
      if (!newExe.existsSync()) {
        throw Exception('安装包内容异常（缺少 $_exeName）');
      }

      await _runUpgradeScript(workDir.path, extractDir.path);
    } catch (e) {
      _fail(true, e.toString());
    }
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(_repoApi));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'quick_launch');

      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('GitHub 返回 ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      return json.decode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// 从 release assets 中找到 zip 安装包的下载地址
  String? _findZipUrl(Map<String, dynamic> data) {
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map && a['name'] == _zipName) {
          return a['browser_download_url'] as String?;
        }
      }
    }
    return null;
  }

  Future<void> _download(String url, File saveTo) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'quick_launch');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('下载失败（HTTP ${response.statusCode}）');
      }

      final total = response.contentLength;
      final sink = saveTo.openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          state.value = UpdateState(
            phase: UpdatePhase.downloading,
            latestVersion: state.value.latestVersion,
            progress: received / total,
          );
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// 优先用 Windows 自带 tar 解压（快），失败时回退 PowerShell Expand-Archive
  Future<void> _extract(File zipFile, Directory target) async {
    final tar = await Process.run(
      'tar',
      ['-xf', zipFile.path, '-C', target.path],
    );
    if (tar.exitCode == 0) return;

    final ps = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Expand-Archive -Path "${zipFile.path}" '
          '-DestinationPath "${target.path}" -Force',
    ]);
    if (ps.exitCode != 0) {
      throw Exception('解压失败: ${ps.stderr}');
    }
  }

  /// 生成并执行升级脚本：等待应用退出 → 覆盖文件 → 重启
  Future<void> _runUpgradeScript(String workPath, String extractPath) async {
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final batFile = File('$workPath\\update.bat');
    final writable = _isDirWritable(installDir);

    // bat 里 ping 用于延时（timeout 命令在无控制台时不可用）
    batFile.writeAsStringSync('''
@echo off
ping -n 4 127.0.0.1 >nul
taskkill /f /im $_exeName >nul 2>&1
xcopy /e /i /y "$extractPath\\*" "$installDir\\" >nul
if errorlevel 1 exit 1
start "" "$installDir\\$_exeName"
''');

    if (writable) {
      // 目录可写：直接后台执行脚本，随后退出应用
      await Process.start('cmd', ['/c', batFile.path]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    }

    // 目录不可写（如 Program Files）：请求管理员权限执行
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Start-Process cmd.exe -ArgumentList '/c \"${batFile.path}\"' "
            '-Verb RunAs -WindowStyle Hidden',
      ]);
      if (result.exitCode != 0) {
        throw Exception('未获得管理员权限');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    } catch (e) {
      _fail(true, '需要管理员权限才能完成安装: $e');
    }
  }

  bool _isDirWritable(String dir) {
    try {
      final probe = File(
        '$dir\\.ql_write_test_${DateTime.now().millisecondsSinceEpoch}',
      );
      final handle = probe.openSync(mode: FileMode.write);
      handle.closeSync();
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _fail(bool installError, String message) {
    state.value = UpdateState(
      phase: installError ? UpdatePhase.installFailed : UpdatePhase.checkFailed,
      latestVersion: state.value.latestVersion,
      error: message,
    );
  }

  /// 比较版本号（容忍非数字后缀，如 2.2.3-beta）
  bool _isNewer(String latest) {
    List<int> parse(String v) =>
        v.split(RegExp(r'[.+-]')).map((p) => int.tryParse(p) ?? 0).toList();
    final currentParts = parse(currentVersion);
    final latestParts = parse(latest);
    for (int i = 0; i < 3; i++) {
      final cur = i < currentParts.length ? currentParts[i] : 0;
      final lat = i < latestParts.length ? latestParts[i] : 0;
      if (lat > cur) return true;
      if (lat < cur) return false;
    }
    return false;
  }
}
