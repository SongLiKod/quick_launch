import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/launch_item.dart';
import '../services/item_service.dart';
import '../services/group_service.dart';
import '../services/launch_service.dart';

/// 全局快速搜索弹窗（Spotlight 风格）
/// 通过全局热键触发，实时搜索所有启动项并快速启动
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key});

  /// 展示搜索覆盖层
  static void show(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) => const SearchOverlay(),
    );
  }

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _overlayFocusNode = FocusNode();

  List<LaunchItem> _allItems = [];
  List<LaunchItem> _filteredItems = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _allItems = List.from(ItemService().items.value);
    _filteredItems = List.from(_allItems);
    _searchFocusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _overlayFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = List.from(_allItems);
      } else {
        _filteredItems = _allItems
            .where((item) =>
                item.name.toLowerCase().contains(query) ||
                item.targetPath.toLowerCase().contains(query))
            .toList();
      }
      if (_selectedIndex >= _filteredItems.length) {
        _selectedIndex = _filteredItems.isEmpty ? 0 : _filteredItems.length - 1;
      }
    });
  }

  void _launchItem(LaunchItem item) {
    Navigator.of(context).pop();
    LaunchService().launch(item);
  }

  String? _getGroupName(String? groupId) {
    if (groupId == null) return null;
    final groups = GroupService().groups.value;
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    return group?.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filteredItems;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 64),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 500),
            decoration: BoxDecoration(
              color: theme.dialogTheme.backgroundColor ??
                  theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Focus(
              focusNode: _overlayFocusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _selectedIndex =
                          (_selectedIndex + 1) % items.length;
                    });
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _selectedIndex = (_selectedIndex - 1 + items.length) %
                          items.length;
                    });
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.enter) {
                    if (items.isNotEmpty &&
                        _selectedIndex >= 0 &&
                        _selectedIndex < items.length) {
                      _launchItem(items[_selectedIndex]);
                      return KeyEventResult.handled;
                    }
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ---- 搜索输入框 ----
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            color: theme.colorScheme.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: '搜索启动项...',
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
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          '${items.length}项',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  // ---- 结果列表 ----
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('没有匹配的启动项',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final item = items[i];
                          final selected = i == _selectedIndex;
                          final groupName = _getGroupName(item.groupId);
                          return InkWell(
                            onTap: () => _launchItem(item),
                            onHover: (_) {
                              if (_selectedIndex != i) {
                                setState(() => _selectedIndex = i);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.4)
                                    : null,
                                border: Border(
                                  bottom: BorderSide(
                                    color: theme.dividerColor
                                        .withValues(alpha: 0.15),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // 图标
                                  _buildItemIcon(item),
                                  const SizedBox(width: 12),
                                  // 名称+路径
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.targetPath,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 类型标签
                                  _buildTypeLabel(item),
                                  if (groupName != null) ...[
                                    const SizedBox(width: 4),
                                    _buildGroupBadge(groupName),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  // ---- 底部快捷键提示 ----
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    child: Row(
                      children: [
                        _bottomHint('↑↓', '选择'),
                        const SizedBox(width: 12),
                        _bottomHint('⏎', '启动'),
                        const SizedBox(width: 12),
                        _bottomHint('Esc', '关闭'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          desc,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildItemIcon(LaunchItem item) {
    final (icon, color) = switch (item.type) {
      ItemType.executable =>
        (Icons.miscellaneous_services, Colors.blue),
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
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
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
      child: Text(
        groupName,
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }
}
