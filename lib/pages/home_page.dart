import 'dart:math';
import 'package:flutter/material.dart';
import '../models/launch_item.dart';
import '../services/item_service.dart';
import '../services/hotkey_service.dart';
import '../services/launch_service.dart';
import '../services/system_commands.dart';
import '../services/settings_service.dart';
import '../services/group_service.dart';
import '../widgets/item_tile.dart';
import '../widgets/add_item_dialog.dart';
import '../widgets/group_manage_dialog.dart';
import '../widgets/group_hotkey_overlay.dart';
import '../widgets/scan_import_dialog.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ItemService _itemService = ItemService();
  final GroupService _groupService = GroupService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedGroupId; // null = 全部

  @override
  void initState() {
    super.initState();
    SettingsService().sortMode.addListener(_onChanged);
    SettingsService().columnCount.addListener(_onChanged);
    _groupService.groups.addListener(_onChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    HotkeyService().groupHotkeyTrigger.addListener(_onGroupHotkeyTriggered);
  }

  @override
  void dispose() {
    SettingsService().sortMode.removeListener(_onChanged);
    SettingsService().columnCount.removeListener(_onChanged);
    _groupService.groups.removeListener(_onChanged);
    _searchController.dispose();
    HotkeyService().groupHotkeyTrigger.removeListener(_onGroupHotkeyTriggered);
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
  }

  void _onGroupHotkeyTriggered() {
    final groupId = HotkeyService().groupHotkeyTrigger.value;
    if (groupId == null) return;
    // 清空触发器，防止重复触发
    HotkeyService().groupHotkeyTrigger.value = null;
    final groups = _groupService.groups.value;
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) return;
    if (!mounted) return;
    GroupHotkeyOverlay.show(context, group);
  }

  void _openGroupManage() {
    showDialog(
      context: context,
      builder: (_) => const GroupManageDialog(),
    );
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<LaunchItem>(
      context: context,
      builder: (ctx) => const AddItemDialog(),
    );
    if (result != null) {
      _itemService.addItem(result);
      if (result.hotkeyVirtualKey != null) {
        HotkeyService().registerItemHotkey(result);
      }
    }
  }

  Future<void> _showScanImportDialog() async {
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => const ScanImportDialog(),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功导入 $count 个启动项'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  Widget _buildGroupFilterBar() {
    final groups = _groupService.groups.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildGroupChip('全部', null),
                  ...groups.map((g) => _buildGroupChip(g.name, g.id,
                      color: Color(g.colorValue))),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '管理分组',
            onPressed: _openGroupManage,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupChip(String label, String? groupId,
      {Color? color}) {
    final selected = _selectedGroupId == groupId;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        selectedColor: color?.withValues(alpha: 0.2),
        checkmarkColor: color,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          setState(() => _selectedGroupId = groupId);
        },
      ),
    );
  }

  String? _getGroupName(String? groupId) {
    if (groupId == null) return null;
    final group = _groupService.groups.value.where((g) => g.id == groupId).firstOrNull;
    return group?.name;
  }

  Widget _buildGridLayout(List<LaunchItem> items, int cols) {
    // 将 items 按列数分组为行
    final rows = <List<LaunchItem>>[];
    for (int i = 0; i < items.length; i += cols) {
      rows.add(items.sublist(i, min(i + cols, items.length)));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: rows.length,
      itemBuilder: (_, rowIndex) {
        final row = rows[rowIndex];
        return SizedBox(
          height: 56,
          child: Row(
            children: [
              for (int i = 0; i < row.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 12 : 4,
                      right: i == row.length - 1 ? 12 : 4,
                    ),
                    child: ItemTile(
                      key: ValueKey(row[i].id),
                      item: row[i],
                      isGridMode: true,
                      groupName: _selectedGroupId == null
                          ? _getGroupName(row[i].groupId)
                          : null,
                    ),
                  ),
                ),
              // 空位补齐，保持对齐
              if (row.length < cols)
                for (int i = 0; i < cols - row.length; i++)
                  const Expanded(child: SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 手动排序模式下才启用拖拽，多列模式禁用拖拽
    final sortMode = SettingsService().sortMode.value;
    final columnCount = SettingsService().columnCount.value;
    final enableDrag = sortMode == SortMode.manual && columnCount <= 1;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('快速启动'),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
          PopupMenuButton<LaunchItem>(
            tooltip: '系统命令',
            icon: const Icon(Icons.power_settings_new),
            onSelected: (item) => LaunchService().launch(item),
            itemBuilder: (_) => SystemCommands.builtinCommands.map((cmd) =>
              PopupMenuItem(value: cmd, child: Text(cmd.name)),
            ).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildGroupFilterBar(),
          Expanded(
            child: ValueListenableBuilder<List<LaunchItem>>(
              valueListenable: _itemService.items,
              builder: (_, list, _) {
                // 按分组筛选
                var filtered = list;
                if (_selectedGroupId != null) {
                  filtered = list
                      .where((item) => item.groupId == _selectedGroupId)
                      .toList();
                }
                // 按搜索词筛选
                if (_searchQuery.isNotEmpty) {
                  filtered = filtered
                      .where((item) =>
                          item.name.toLowerCase().contains(_searchQuery) ||
                          item.targetPath.toLowerCase().contains(_searchQuery))
                      .toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty ? '没有匹配的启动项' : '点击右下角 + 添加启动项',
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                if (columnCount > 1) {
                  return _buildGridLayout(filtered, columnCount);
                }

                if (enableDrag) {
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: filtered.length,
                    buildDefaultDragHandles: false,
                    itemBuilder: (_, i) => ItemTile(
                      key: ValueKey(filtered[i].id),
                      item: filtered[i],
                      index: i,
                      groupName: _selectedGroupId == null
                          ? _getGroupName(filtered[i].groupId)
                          : null,
                    ),
                    onReorderItem: (oldIndex, newIndex) {
                      _itemService.reorderItem(oldIndex, newIndex);
                    },
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => ItemTile(
                    key: ValueKey(filtered[i].id),
                    item: filtered[i],
                    groupName: _selectedGroupId == null
                        ? _getGroupName(filtered[i].groupId)
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan',
            onPressed: _showScanImportDialog,
            tooltip: '批量扫描导入',
            child: const Icon(Icons.manage_search, size: 20),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: _showAddDialog,
            tooltip: '添加启动项',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
