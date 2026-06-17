import 'dart:convert';
import 'dart:io';
import '../models/launch_item.dart';

/// 扫描结果中的单个项
class ScannedItem {
  final String name;
  final String targetPath;
  final ItemType type;
  bool selected;

  ScannedItem({
    required this.name,
    required this.targetPath,
    required this.type,
    this.selected = true,
  });
}

/// 文件夹扫描的过滤条件
class ScanFilter {
  bool includeExe;
  bool includeBat;
  bool includeFolder;
  List<String> customExtensions;
  bool includeSubfolders;

  ScanFilter({
    this.includeExe = true,
    this.includeBat = true,
    this.includeFolder = false,
    List<String>? customExtensions,
    this.includeSubfolders = true,
  }) : customExtensions = customExtensions ?? [];

  bool get hasAnyFilter =>
      includeExe || includeBat || includeFolder || customExtensions.isNotEmpty;

  bool matchesExtension(String ext) {
    final lower = ext.toLowerCase();
    if (includeExe && lower == '.exe') return true;
    if (includeBat && (lower == '.bat' || lower == '.cmd')) return true;
    if (customExtensions.any((e) => e.trim().toLowerCase() == lower)) {
      return true;
    }
    return false;
  }
}

/// 统一扫描服务：文件夹扫描 + 已安装软件扫描
class ScanUtil {
  // ──────────────── 方案二：文件夹扫描 ────────────────

  static Future<List<ScannedItem>> scanDirectory(
    String directoryPath,
    ScanFilter filter,
  ) async {
    final results = <ScannedItem>[];
    final dir = Directory(directoryPath);

    if (!await dir.exists()) return results;

    try {
      await for (final entity
          in dir.list(recursive: filter.includeSubfolders)) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          final dot = path.lastIndexOf('.');
          if (dot == -1) continue;
          final extension = path.substring(dot);

          if (!filter.matchesExtension(extension)) continue;

          final fullName = entity.path.split('\\').last.split('/').last;
          final displayName = _stripExtension(fullName);

          results.add(ScannedItem(
            name: displayName,
            targetPath: entity.path,
            type: _detectTypeFromExtension(extension),
          ));
        } else if (entity is Directory && filter.includeFolder) {
          if (entity.path == directoryPath) continue;
          final name = entity.path.split('\\').last.split('/').last;
          results.add(ScannedItem(
            name: name,
            targetPath: entity.path,
            type: ItemType.folder,
          ));
        }
      }
    } catch (_) {}

    // 路径去重
    final seen = <String>{};
    results.removeWhere((item) => !seen.add(item.targetPath.toLowerCase()));

    return results;
  }

  // ──────────────── 方案一：扫描已安装软件 ────────────────

  /// 从开始菜单 + 桌面 + 注册表扫描已安装的应用程序
  static Future<List<ScannedItem>> scanInstalledSoftware() async {
    final results = <ScannedItem>[];
    final seen = <String>{};

    // 1. 开始菜单快捷方式
    results.addAll(await _scanStartMenu(seen));

    // 2. 桌面快捷方式
    results.addAll(await _scanDesktop(seen));

    // 3. 注册表已卸载列表
    results.addAll(await _scanRegistry(seen));

    return results;
  }

  /// 扫描开始菜单 Programs 目录
  static Future<List<ScannedItem>> _scanStartMenu(Set<String> seen) async {
    final results = <ScannedItem>[];

    final dirs = <String>[
      '${Platform.environment['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs',
      '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs',
    ];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.lnk')) {
            await _tryAddLnk(results, seen, entity.path, '开始菜单');
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// 扫描用户桌面和公共桌面
  static Future<List<ScannedItem>> _scanDesktop(Set<String> seen) async {
    final results = <ScannedItem>[];

    final dirs = <String>[
      '${Platform.environment['USERPROFILE']}\\Desktop',
      '${Platform.environment['PUBLIC']}\\Desktop',
      '${Platform.environment['USERPROFILE']}\\OneDrive\\Desktop',
    ];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.lnk')) {
            await _tryAddLnk(results, seen, entity.path, '桌面');
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// 尝试解析并添加一个 .lnk 快捷方式
  static Future<void> _tryAddLnk(
    List<ScannedItem> results,
    Set<String> seen,
    String lnkPath,
    String source,
  ) async {
    try {
      final target = await _resolveLnkTarget(lnkPath);
      if (target == null ||
          target.isEmpty ||
          seen.contains(target.toLowerCase())) {
        return;
      }

      final ext = target.toLowerCase();
      // 只保留可执行文件和批处理
      if (!ext.endsWith('.exe') &&
          !ext.endsWith('.bat') &&
          !ext.endsWith('.cmd')) {
        return;
      }

      seen.add(target.toLowerCase());

      final name = _stripExtension(
          lnkPath.split('\\').last.split('/').last);

      results.add(ScannedItem(
        name: name,
        targetPath: target,
        type: _detectFromPath(target),
      ));
    } catch (_) {}
  }

  /// 用 PowerShell COM 对象解析 .lnk 目标路径
  static Future<String?> _resolveLnkTarget(String lnkPath) async {
    try {
      // 转义路径中的单引号
      final safePath = lnkPath.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "(New-Object -ComObject WScript.Shell).CreateShortcut('$safePath').TargetPath",
        ],
        runInShell: true,
        // PowerShell 的输出在 stdout
      );
      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        return output.isNotEmpty ? output : null;
      }
    } catch (_) {}
    return null;
  }

  /// 从注册表 Uninstall 项扫描已安装软件
  static Future<List<ScannedItem>> _scanRegistry(Set<String> seen) async {
    final results = <ScannedItem>[];

    // PowerShell 脚本：读取两个注册表路径的 Uninstall 信息
    // 输出 JSON 格式： [{DisplayName, InstallLocation, DisplayIcon}]
    final psScript = r'''
$paths = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
);

$result = @();
foreach ($path in $paths) {
  Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.DisplayName;
    if ([string]::IsNullOrEmpty($name)) { return; }
    $loc = $_.InstallLocation;
    $icon = $_.DisplayIcon;
    $target = '';
    if ($loc -and (Test-Path $loc)) {
      $target = $loc;
    } elseif ($icon -and (Test-Path $icon)) {
      $target = $icon;
    } elseif ($loc) {
      $target = $loc;
    }
    if ([string]::IsNullOrEmpty($target)) { return; }

    # 如果目标是个文件但不是 exe，取其目录
    if ((Test-Path $target -PathType Leaf) -and $target -notmatch '\.exe$') {
      $target = Split-Path $target -Parent;
    }

    # 找到目录下的主 exe
    if (Test-Path $target -PathType Container) {
      $exe = Get-ChildItem $target -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1;
      if ($exe) {
        $target = $exe.FullName;
      } else {
        return;
      }
    }

    if (Test-Path $target) {
      $result += @{ Name = $name; TargetPath = $target };
    }
  }
}

# 去重后输出 JSON
$result | Sort-Object { $_.TargetPath } -Unique | ConvertTo-Json -Compress
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        if (output.isEmpty) return results;

        final List<dynamic> items = json.decode(output);
        for (final item in items) {
          final name = item['Name'] as String?;
          final targetPath = item['TargetPath'] as String?;
          if (name == null ||
              targetPath == null ||
              targetPath.isEmpty ||
              seen.contains(targetPath.toLowerCase())) {
            continue;
          }

          final ext = targetPath.toLowerCase();
          if (!ext.endsWith('.exe') &&
              !ext.endsWith('.bat') &&
              !ext.endsWith('.cmd')) {
            continue;
          }

          seen.add(targetPath.toLowerCase());

          results.add(ScannedItem(
            name: name,
            targetPath: targetPath,
            type: _detectFromPath(targetPath),
          ));
        }
      }
    } catch (_) {}

    return results;
  }

  // ──────────────── 辅助方法 ────────────────

  static String _stripExtension(String fileName) {
    if (fileName.endsWith('.lnk')) {
      return fileName.substring(0, fileName.length - 4);
    }
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  static ItemType _detectTypeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.exe':
        return ItemType.executable;
      case '.bat':
      case '.cmd':
        return ItemType.batScript;
      default:
        return ItemType.file;
    }
  }

  static ItemType _detectFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.exe')) return ItemType.executable;
    if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
      return ItemType.batScript;
    }
    return ItemType.file;
  }
}
