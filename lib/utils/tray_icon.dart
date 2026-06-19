import 'dart:io';
import 'package:flutter/services.dart';

/// 从 asset 中加载 logo.ico 并保存到临时文件
class TrayIconHelper {
  /// 返回系统临时目录中默认图标的路径
  static Future<String> saveIconToFile() async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}\\quick_launch_default_icon.ico');
    if (await file.exists()) return file.path;

    final data = await rootBundle.load('assets/logo.ico');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }

  /// 返回系统临时目录中红色暂停图标的路径
  static Future<String> savePausedIconToFile() async {
    final dir = Directory.systemTemp;
    final file = File('${dir.path}\\quick_launch_paused_icon.ico');
    if (await file.exists()) return file.path;

    final data = await rootBundle.load('assets/logo-red32.ico');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }
}
