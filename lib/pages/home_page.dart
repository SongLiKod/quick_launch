import 'package:flutter/material.dart';
import '../models/launch_item.dart';
import '../services/item_service.dart';
import '../services/hotkey_service.dart';
import '../services/launch_service.dart';
import '../services/system_commands.dart';
import '../services/settings_service.dart';
import '../widgets/item_tile.dart';
import '../widgets/add_item_dialog.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ItemService _itemService = ItemService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    SettingsService().sortMode.addListener(_onSortModeChanged);
    SettingsService().columnCount.addListener(_onSortModeChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    SettingsService().sortMode.removeListener(_onSortModeChanged);
    SettingsService().columnCount.removeListener(_onSortModeChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSortModeChanged() {
    setState(() {});
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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 手动排序模式下才启用拖拽
    final sortMode = SettingsService().sortMode.value;
    final enableDrag = sortMode == SortMode.manual;

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
      body: ValueListenableBuilder<List<LaunchItem>>(
        valueListenable: _itemService.items,
        builder: (_, list, _) {
          final filtered = _searchQuery.isEmpty
              ? list
              : list.where((item) =>
                  item.name.toLowerCase().contains(_searchQuery) ||
                  item.targetPath.toLowerCase().contains(_searchQuery)).toList();

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

          final columns = SettingsService().columnCount.value;
          final useGrid = columns > 1 && !enableDrag;

          if (useGrid) {
            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => ItemTile(
                key: ValueKey(filtered[i].id),
                item: filtered[i],
                compact: true,
              ),
            );
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
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
