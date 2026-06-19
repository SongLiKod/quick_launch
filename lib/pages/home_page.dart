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

  // 批量选择模式
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  int get _selectedCount => _selectedIds.length;

  List<LaunchItem> _getFilteredList(List<LaunchItem> list) {
    var filtered = list;
    if (_selectedGroupId != null) {
      filtered = list
          .where((item) => item.groupId == _selectedGroupId)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      filtered = filtered
          .where((item) =>
              item.name.toLowerCase().contains(q) ||
              item.targetPath.toLowerCase().contains(q) ||
              item.aliases.any((a) => a.toLowerCase().contains(q)))
          .toList();
    }
    return filtered;
  }

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

  // ── 批量选择模式 ──

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedIds.clear();
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认批量删除'),
        content: Text('确定删除已选的 $_selectedCount 个启动项？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // 注销所有选中项的热键
    final allItems = _itemService.items.value;
    for (final item in allItems) {
      if (_selectedIds.contains(item.id) && item.hotkeyVirtualKey != null) {
        HotkeyService().unregisterItemHotkey(item);
      }
    }

    final count = _selectedIds.length;
    await _itemService.removeItems(_selectedIds.toList());
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $count 个启动项'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _batchMove() async {
    if (_selectedIds.isEmpty) return;
    final groups = _groupService.groups.value;
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无分组，请先创建分组'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    String? targetGroupId;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移动到分组'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('无分组'),
                leading: Icon(
                  Icons.block,
                  color: Colors.grey[400],
                ),
                selected: targetGroupId == null,
                onTap: () {
                  targetGroupId = null;
                  Navigator.of(ctx).pop('__no_group__');
                },
              ),
              ...groups.map((g) => ListTile(
                    title: Text(g.name),
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(g.colorValue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    selected: targetGroupId == g.id,
                    onTap: () {
                      targetGroupId = g.id;
                      Navigator.of(ctx).pop(g.id);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;

    final count = _selectedIds.length;
    await _groupService.moveItemsToGroup(
        _selectedIds.toList(), result == '__no_group__' ? null : result);
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已移动 $count 个启动项'),
        behavior: SnackBarBehavior.floating,
      ),
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

  Color? _getGroupColor(String? groupId) {
    if (groupId == null) return null;
    final group = _groupService.groups.value.where((g) => g.id == groupId).firstOrNull;
    return group?.color;
  }

  Widget _buildBatchActionBar() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(
              '已选 $_selectedCount 项',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _selectedIds.isEmpty ? null : _batchMove,
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              label: const Text('移动'),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: _selectedIds.isEmpty ? null : _batchDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
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
                      groupColor: _selectedGroupId == null
                          ? _getGroupColor(row[i].groupId)
                          : null,
                      selectMode: _selectionMode,
                      isSelected: _selectedIds.contains(row[i].id),
                      onSelect: (_) => _toggleItemSelection(row[i].id),
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
            icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
            tooltip: _selectionMode ? '退出选择' : '批量操作',
            onPressed: _toggleSelectionMode,
          ),
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
                final filtered = _getFilteredList(list);

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
                      groupColor: _selectedGroupId == null
                          ? _getGroupColor(filtered[i].groupId)
                          : null,
                      selectMode: _selectionMode,
                      isSelected: _selectedIds.contains(filtered[i].id),
                      onSelect: (_) => _toggleItemSelection(filtered[i].id),
                    ),
                    onReorderItem: (oldIndex, newIndex) {
                      if (!_selectionMode) {
                        _itemService.reorderItem(oldIndex, newIndex);
                      }
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
                    groupColor: _selectedGroupId == null
                        ? _getGroupColor(filtered[i].groupId)
                        : null,
                    selectMode: _selectionMode,
                    isSelected: _selectedIds.contains(filtered[i].id),
                    onSelect: (_) => _toggleItemSelection(filtered[i].id),
                  ),
                );
              },
            ),
          ),
          if (_selectionMode) _buildBatchActionBar(),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : Column(
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
