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
        title: const Text('快速启动'),
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
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.launch, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '点击右下角 + 添加启动项',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          if (enableDrag) {
            return ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: list.length,
              buildDefaultDragHandles: false,
              itemBuilder: (_, i) => ItemTile(
                key: ValueKey(list[i].id),
                item: list[i],
                index: i,
              ),
              onReorderItem: (oldIndex, newIndex) {
                _itemService.reorderItem(oldIndex, newIndex);
              },
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: list.length,
            itemBuilder: (_, i) => ItemTile(
              key: ValueKey(list[i].id),
              item: list[i],
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
