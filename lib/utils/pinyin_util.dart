import 'package:lpinyin/lpinyin.dart';
import '../models/launch_item.dart';

/// 拼音搜索工具：为中文启动项名称生成首字母/全拼索引
/// 例如 "记事本" -> 首字母 "jsb"、全拼 "jishiben"
class PinyinUtil {
  static final Map<String, String> _shortCache = {};
  static final Map<String, String> _fullCache = {};

  /// 拼音首字母：记事本 -> jsb；非中文字符原样保留
  static String shortPinyin(String text) {
    if (text.isEmpty) return '';
    return _shortCache.putIfAbsent(text, () {
      try {
        return PinyinHelper.getShortPinyin(text).toLowerCase();
      } catch (_) {
        return text.toLowerCase();
      }
    });
  }

  /// 全拼（无分隔符）：记事本 -> jishiben
  static String fullPinyin(String text) {
    if (text.isEmpty) return '';
    return _fullCache.putIfAbsent(text, () {
      try {
        return PinyinHelper.getPinyin(text, separator: '').toLowerCase();
      } catch (_) {
        return text.toLowerCase();
      }
    });
  }

  /// 构建启动项的可搜索文本（名称/路径/别名/分组 + 拼音首字母/全拼），全部小写
  static String itemHaystack(
    LaunchItem item, {
    String? groupName,
    String? typeLabel,
  }) {
    final parts = <String>[
      item.name,
      item.targetPath,
      item.aliases.join(' '),
      item.type.name,
      if (groupName != null && groupName.isNotEmpty) groupName,
      if (typeLabel != null && typeLabel.isNotEmpty) typeLabel,
      // 拼音索引
      shortPinyin(item.name),
      fullPinyin(item.name),
      if (groupName != null && groupName.isNotEmpty) ...[
        shortPinyin(groupName),
        fullPinyin(groupName),
      ],
      for (final a in item.aliases) ...[shortPinyin(a), fullPinyin(a)],
    ];
    return parts.join(' ').toLowerCase();
  }
}
