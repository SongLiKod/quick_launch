import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:win32/win32.dart';
import '../models/launch_item.dart';
import '../services/item_service.dart';
import '../services/group_service.dart';
import '../services/launch_service.dart';
import '../utils/pinyin_util.dart';
import '../app.dart';

/// 搜索结果行：启动项
class ItemSearchRow {
  final LaunchItem item;
  ItemSearchRow(this.item);
}

/// 搜索结果行：直达操作（命令 / 网址 / 计算 / 网页搜索）
class ActionSearchRow {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String badge;
  final Color badgeColor;
  final VoidCallback onRun;

  ActionSearchRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onRun,
  });
}

/// 全局快速搜索页面 — 按下全局搜索热键后弹出
/// 以无边框小窗口形式呈现，类似 Spotlight / PowerToys Run 风格。
/// 支持：拼音首字母匹配、>命令直达、网址直达、算式计算、无结果网页搜索兜底。
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key});

  static void open() {
    _enterSearchMode();
    final nav = navigatorKey.currentState;
    nav?.push(
      MaterialPageRoute(
        builder: (_) => const SearchOverlay(),
        fullscreenDialog: true,
      ),
    );
  }

  static int _savedStyle = 0;
  static double _savedWidth = 0;
  static double _savedHeight = 0;
  static double _savedLeft = 0;
  static double _savedTop = 0;

  static void _enterSearchMode() {
    final hwnd = appWindow.handle;
    if (hwnd == null) return;

    _savedStyle = GetWindowLongPtr(hwnd, GWL_STYLE);
    _savedWidth = appWindow.size.width;
    _savedHeight = appWindow.size.height;
    _savedLeft = appWindow.position.dx;
    _savedTop = appWindow.position.dy;

    const removedStyle = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU;
    final newStyle = _savedStyle & ~removedStyle;
    SetWindowLongPtr(hwnd, GWL_STYLE, newStyle);

    SetWindowPos(
      hwnd, HWND_NOTOPMOST, 0, 0, 620, 500,
      SWP_NOMOVE | SWP_FRAMECHANGED,
    );

    final screenW = GetSystemMetrics(SM_CXSCREEN);
    final screenH = GetSystemMetrics(SM_CYSCREEN);
    final x = (screenW - 620) ~/ 2;
    final y = (screenH - 500) ~/ 2;
    SetWindowPos(hwnd, HWND_NOTOPMOST, x, y, 620, 500, SWP_NOZORDER);

    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
  }

  static void _exitSearchMode() {
    final hwnd = appWindow.handle;
    if (hwnd == null) return;

    // 先隐藏窗口 — 防止后续样式恢复时主界面闪现
    ShowWindow(hwnd, SW_HIDE);

    // 隐藏后再恢复窗口样式和几何尺寸（用户看不到）
    SetWindowLongPtr(hwnd, GWL_STYLE, _savedStyle);

    if (_savedWidth > 0 && _savedHeight > 0) {
      SetWindowPos(
        hwnd, HWND_NOTOPMOST,
        _savedLeft.toInt(), _savedTop.toInt(),
        _savedWidth.toInt(), _savedHeight.toInt(),
        SWP_FRAMECHANGED,
      );
    } else {
      SetWindowPos(
        hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED,
      );
    }
  }

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<LaunchItem> _allItems = [];
  List<Object> _rows = [];
  int _selectedIndex = 0;
  final Set<String> _aliasMatchIds = {};

  /// 常见顶级域名，用于判断输入是否为网址（避免把 xxx.txt 误判为网址）
  static const Set<String> _knownTlds = {
    'com', 'net', 'org', 'cn', 'io', 'cc', 'me', 'top', 'dev', 'app', 'ai',
    'co', 'info', 'xyz', 'tv', 'edu', 'gov', 'biz', 'club', 'vip', 'wiki',
    'link', 'pro', 'tech', 'site', 'online', 'store', 'shop', 'blog', 'cloud',
    'run', 'fun', 'live', 'plus', 'news', 'mobi', 'name', 'fm', 'im', 'sh',
    'it', 'uk', 'us', 'jp', 'kr', 'de', 'fr', 'ru', 'br', 'in', 'ca', 'au',
    'hk', 'tw', 'sg', 'la', 'ly', 'to', 'id', 'gg', 'ph', 'so', 'win',
  };

  @override
  void initState() {
    super.initState();
    _allItems = List.from(ItemService().items.value);
    _rows = _allItems.map((e) => ItemSearchRow(e)).toList();
    _searchFocusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final raw = _searchController.text.trim();
    final query = raw.toLowerCase();
    final groups = GroupService().groups.value;
    setState(() {
      _aliasMatchIds.clear();
      _rows = [];

      if (query.isEmpty) {
        _rows = _allItems.map((e) => ItemSearchRow(e)).toList();
      } else {
        // ── 1. 直达操作（排在最前，回车即可执行）──
        if (raw.startsWith('>')) {
          // >命令：在新 CMD 窗口执行
          final cmd = raw.substring(1).trim();
          if (cmd.isNotEmpty) {
            _rows.add(ActionSearchRow(
              icon: Icons.terminal,
              iconColor: Colors.teal,
              title: '执行命令: $cmd',
              subtitle: '在新 CMD 窗口中运行',
              badge: '命令',
              badgeColor: Colors.teal,
              onRun: () => _runCommand(cmd),
            ));
          }
        } else {
          // 网址直达
          final url = _detectUrl(raw);
          if (url != null) {
            _rows.add(ActionSearchRow(
              icon: Icons.language,
              iconColor: Colors.blue,
              title: '打开网址: $url',
              subtitle: '使用默认浏览器打开',
              badge: '网址',
              badgeColor: Colors.blue,
              onRun: () => _launchLink(url, '打开网址'),
            ));
          }

          // 算式计算
          final result = _evalMath(raw);
          if (result != null) {
            _rows.add(ActionSearchRow(
              icon: Icons.calculate_outlined,
              iconColor: Colors.purple,
              title: '= $result',
              subtitle: '回车复制结果',
              badge: '计算',
              badgeColor: Colors.purple,
              onRun: () => _copyResult(result),
            ));
          }
        }

        // ── 2. 匹配启动项（名称/路径/别名/分组 + 拼音首字母/全拼）──
        for (final item in _allItems) {
          final typeLabel = switch (item.type) {
            ItemType.executable => '应用',
            ItemType.batScript => '脚本',
            ItemType.file => '文件',
            ItemType.folder => '文件夹',
            ItemType.system => '系统',
            ItemType.command => '命令',
            ItemType.link => '链接',
          };
          final groupName = item.groupId == null
              ? ''
              : groups
                  .where((g) => g.id == item.groupId)
                  .map((g) => g.name)
                  .firstOrNull ??
                  '';
          final haystack = PinyinUtil.itemHaystack(
            item,
            groupName: groupName,
            typeLabel: typeLabel,
          );
          if (haystack.contains(query)) {
            _rows.add(ItemSearchRow(item));
            if (item.aliases
                .any((a) => a.toLowerCase().contains(query))) {
              _aliasMatchIds.add(item.id);
            }
          }
        }

        // ── 3. 无匹配项时网页搜索兜底 ──
        final hasItemRows = _rows.any((r) => r is ItemSearchRow);
        if (!hasItemRows && !raw.startsWith('>') && _detectUrl(raw) == null) {
          _rows.add(ActionSearchRow(
            icon: Icons.travel_explore,
            iconColor: Colors.blue,
            title: '百度搜索: $raw',
            subtitle: '在浏览器中搜索',
            badge: '搜索',
            badgeColor: Colors.blue,
            onRun: () => _webSearch('baidu', raw),
          ));
          _rows.add(ActionSearchRow(
            icon: Icons.travel_explore,
            iconColor: Colors.red,
            title: 'Google 搜索: $raw',
            subtitle: '在浏览器中搜索',
            badge: '搜索',
            badgeColor: Colors.red,
            onRun: () => _webSearch('google', raw),
          ));
        }
      }

      if (_selectedIndex >= _rows.length) {
        _selectedIndex = _rows.isEmpty ? 0 : _rows.length - 1;
      }
    });
  }

  // ── 直达操作执行 ──

  void _runCommand(String cmd) {
    SearchOverlay._exitSearchMode();
    Navigator.of(context).pop();
    LaunchService().launch(LaunchItem(
      id: 'quick_cmd_${DateTime.now().microsecondsSinceEpoch}',
      name: '命令: $cmd',
      targetPath: cmd,
      type: ItemType.command,
    ));
  }

  void _launchLink(String url, String name) {
    SearchOverlay._exitSearchMode();
    Navigator.of(context).pop();
    LaunchService().launch(LaunchItem(
      id: 'quick_link_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      targetPath: url,
      type: ItemType.link,
    ));
  }

  void _webSearch(String engine, String query) {
    final encoded = Uri.encodeComponent(query);
    final url = engine == 'baidu'
        ? 'https://www.baidu.com/s?wd=$encoded'
        : 'https://www.google.com/search?q=$encoded';
    _launchLink(url, '$engine 搜索');
  }

  void _copyResult(String text) {
    Clipboard.setData(ClipboardData(text: text));
    SearchOverlay._exitSearchMode();
    Navigator.of(context).pop();
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('已复制计算结果: $text'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ── 输入识别 ──

  /// 识别网址输入。支持 http(s):// 开头，或 域名.tld 形式（白名单校验 TLD）。
  String? _detectUrl(String text) {
    final t = text.trim();
    if (t.isEmpty || t.contains(' ') || t.contains('\\')) return null;

    if (t.startsWith('http://') || t.startsWith('https://')) return t;

    final m = RegExp(r'^([\w-]+(?:\.[\w-]+)+)(?:/[^\s]*)?$').firstMatch(t);
    if (m == null) return null;
    final host = m.group(1)!;
    final tld = host.substring(host.lastIndexOf('.') + 1).toLowerCase();
    if (!_knownTlds.contains(tld)) return null;
    return 'https://$t';
  }

  /// 简单四则运算求值（支持 + - * / 与括号、小数、正负号），无法解析返回 null。
  String? _evalMath(String text) {
    final t = text.trim();
    if (!RegExp(r'^[\d\s+\-*/().]+$').hasMatch(t)) return null;
    if (!RegExp(r'[+\-*/]').hasMatch(t)) return null;

    final value = _MathParser(t).parse();
    if (value == null || value.isNaN || value.isInfinite) return null;

    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    // 消除浮点误差尾巴，如 0.1+0.2 = 0.300000 → 0.3
    var str = value.toStringAsFixed(6);
    str = str.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return str;
  }

  void _launchItem(LaunchItem item) {
    SearchOverlay._exitSearchMode();
    Navigator.of(context).pop();
    LaunchService().launch(item);
  }

  void _runRow(Object row) {
    switch (row) {
      case ItemSearchRow(item: final item):
        _launchItem(item);
      case ActionSearchRow(onRun: final onRun):
        onRun();
    }
  }

  void _close() {
    SearchOverlay._exitSearchMode();
    Navigator.of(context).pop();
  }

  String? _getGroupName(String? groupId) {
    if (groupId == null) return null;
    final groups = GroupService().groups.value;
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    return group?.name;
  }

  Widget _buildAliasBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: const Text(
        '别名',
        style: TextStyle(fontSize: 10, color: Colors.purple, height: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () {
            if (rows.isEmpty) return;
            setState(() {
              _selectedIndex = (_selectedIndex + 1) % rows.length;
            });
          },
          const SingleActivator(LogicalKeyboardKey.arrowUp): () {
            if (rows.isEmpty) return;
            setState(() {
              _selectedIndex =
                  (_selectedIndex - 1 + rows.length) % rows.length;
            });
          },
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (rows.isNotEmpty &&
                _selectedIndex >= 0 &&
                _selectedIndex < rows.length) {
              _runRow(rows[_selectedIndex]);
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints.expand(),
              decoration: BoxDecoration(
                color: theme.dialogTheme.backgroundColor ??
                    theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildSearchBar(theme, rows.length),
                  if (rows.isEmpty)
                    _buildEmptyState()
                  else
                    Flexible(child: _buildResultList(theme, rows)),
                  _buildBottomBar(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索启动项 · 拼音首字母 · >命令 · 网址 · 算式',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _searchController.clear();
                _searchFocusNode.requestFocus();
              },
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          const SizedBox(width: 8),
          Text('$count项', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.inbox, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('没有启动项', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildResultList(ThemeData theme, List<Object> rows) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        final selected = i == _selectedIndex;
        switch (row) {
          case ItemSearchRow(item: final item):
            return _buildItemTile(theme, item, selected, i);
          case ActionSearchRow():
            return _buildActionTile(theme, row, selected, i);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildItemTile(ThemeData theme, LaunchItem item, bool selected, int i) {
    final groupName = _getGroupName(item.groupId);
    return InkWell(
      onTap: () => _launchItem(item),
      onHover: (_) {
        if (_selectedIndex != i) {
          setState(() => _selectedIndex = i);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : null,
          border: Border(
            bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          children: [
            _buildItemIcon(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.targetPath,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.aliases.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: item.aliases.map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          a,
                          style: const TextStyle(fontSize: 10, color: Colors.purple, height: 1.3),
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildTypeLabel(item),
            if (groupName != null) ...[
              const SizedBox(width: 4),
              _buildGroupBadge(groupName),
            ],
            if (_aliasMatchIds.contains(item.id)) ...[
              const SizedBox(width: 4),
              _buildAliasBadge(),
            ],
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 16),
              tooltip: '复制',
              color: Colors.grey,
              onPressed: () => LaunchService().copyItem(context, item),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    ThemeData theme,
    ActionSearchRow row,
    bool selected,
    int i,
  ) {
    return InkWell(
      onTap: row.onRun,
      onHover: (_) {
        if (_selectedIndex != i) {
          setState(() => _selectedIndex = i);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? row.iconColor.withValues(alpha: 0.12)
              : row.iconColor.withValues(alpha: 0.04),
          border: Border(
            bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          children: [
            Icon(row.icon, size: 22, color: row.iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (row.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      row.subtitle!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: row.badgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: row.badgeColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                row.badge,
                style: TextStyle(fontSize: 10, color: row.badgeColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          _bottomHint('↑↓', '选择'),
          const SizedBox(width: 12),
          _bottomHint('⏎', '执行'),
          const SizedBox(width: 12),
          _bottomHint('Esc', '关闭'),
          const Spacer(),
          Text(
            '>命令  ·  网址直达  ·  算式计算',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _bottomHint(String key, String desc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            key,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 4),
        Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildItemIcon(LaunchItem item) {
    final (icon, color) = switch (item.type) {
      ItemType.executable => (Icons.miscellaneous_services, Colors.blue),
      ItemType.batScript => (Icons.terminal, Colors.orange),
      ItemType.file => (Icons.description, Colors.grey),
      ItemType.folder => (Icons.folder, Colors.amber),
      ItemType.system => (Icons.power_settings_new, Colors.red),
      ItemType.command => (Icons.terminal, Colors.teal),
      ItemType.link => (Icons.link, Colors.blue),
    };
    return Icon(icon, size: 22, color: color);
  }

  Widget _buildTypeLabel(LaunchItem item) {
    final (label, color) = switch (item.type) {
      ItemType.executable => ('应用', Colors.blue),
      ItemType.batScript => ('脚本', Colors.orange),
      ItemType.file => ('文件', Colors.grey),
      ItemType.folder => ('文件夹', Colors.amber),
      ItemType.system => ('系统', Colors.red),
      ItemType.command => ('命令', Colors.teal),
      ItemType.link => ('链接', Colors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _buildGroupBadge(String groupName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Text(groupName, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }
}

/// 极简四则运算解析器（递归下降）：expr → term → factor
class _MathParser {
  final String s;
  int i = 0;

  _MathParser(this.s);

  double? parse() {
    try {
      final v = _expr();
      _ws();
      if (i != s.length) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double _expr() {
    var v = _term();
    while (true) {
      _ws();
      if (_eat('+')) {
        v += _term();
      } else if (_eat('-')) {
        v -= _term();
      } else {
        return v;
      }
    }
  }

  double _term() {
    var v = _factor();
    while (true) {
      _ws();
      if (_eat('*') || _eat('×')) {
        v *= _factor();
      } else if (_eat('/') || _eat('÷')) {
        v /= _factor();
      } else {
        return v;
      }
    }
  }

  double _factor() {
    _ws();
    if (_eat('+')) return _factor();
    if (_eat('-')) return -_factor();
    if (_eat('(')) {
      final v = _expr();
      _ws();
      if (!_eat(')')) throw const FormatException('missing )');
      return v;
    }
    final start = i;
    while (i < s.length && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (i == start) throw const FormatException('number expected');
    return double.parse(s.substring(start, i));
  }

  bool _eat(String c) {
    if (i < s.length && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }
}
