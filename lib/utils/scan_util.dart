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

  /// 判断某扩展名是否符合过滤条件
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

/// 文件夹扫描服务
class ScanUtil {
  /// 扫描指定文件夹，返回匹配条件的文件列表
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
          // dir.list() 在 recursive=true 时也会 yield 子目录
          // 跳过根目录自身
          if (entity.path == directoryPath) continue;
          final name = entity.path.split('\\').last.split('/').last;
          results.add(ScannedItem(
            name: name,
            targetPath: entity.path,
            type: ItemType.folder,
          ));
        }
      }
    } catch (_) {
      // 跳过无法访问的目录
    }

    // 路径去重
    final seen = <String>{};
    results.removeWhere((item) => !seen.add(item.targetPath));

    return results;
  }

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
}
