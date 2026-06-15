import 'dart:io';
import 'package:flutter/services.dart';

/// 从 asset 中加载 logo.ico 并保存到临时文件
class TrayIconHelper {
  /// 返回系统临时目录中 logo.ico 的路径
  /// 如果尚未缓存，会从 asset bundle 读取并写入临时文件
  static Future<String> saveIconToFile() async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}\\quick_launch_default_icon.ico');
    if (await file.exists()) return file.path;

    final data = await rootBundle.load('assets/logo.ico');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }
}
