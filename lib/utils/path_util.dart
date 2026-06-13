import 'dart:io';
import '../models/launch_item.dart';

class PathUtil {
  static ItemType detectType(String path) {
    if (path.isEmpty) return ItemType.file;

    final lower = path.toLowerCase();
    if (lower.endsWith('.exe')) return ItemType.executable;
    if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
      return ItemType.batScript;
    }

    try {
      if (Directory(path).existsSync()) return ItemType.folder;
    } catch (_) {}

    return ItemType.file;
  }

  static String getFileName(String path) {
    try {
      return path.split('\\').last.split('/').last;
    } catch (_) {
      return path;
    }
  }
}
