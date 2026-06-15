import 'package:flutter/material.dart';
import '../models/launch_item.dart';
import '../services/hotkey_service.dart';
import '../services/item_service.dart';
import '../services/launch_service.dart';
import 'add_item_dialog.dart';

class ItemTile extends StatelessWidget {
  final LaunchItem item;
  final int? index;
  final bool compact;

  const ItemTile({super.key, required this.item, this.index, this.compact = false});

  void _onEdit(BuildContext context) async {
    final result = await showDialog<LaunchItem>(
      context: context,
      builder: (ctx) => AddItemDialog(item: item),
    );
    if (result == null) return;

    if (item.hotkeyVirtualKey != null) {
      HotkeyService().unregisterItemHotkey(item);
    }

    ItemService().updateItem(result);

    if (result.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(result);
    }
  }

  void _onDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除"${item.name}"？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (item.hotkeyVirtualKey != null) {
                HotkeyService().unregisterItemHotkey(item);
              }
              ItemService().removeItem(item.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (index != null)
              ReorderableDragStartListener(
                index: index!,
                child: const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.drag_handle, color: Colors.grey),
                ),
              ),
            _buildIcon(32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTypeLabel(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.targetPath,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (item.hotkeyVirtualKey != null) ...[
              _buildHotkeyBadge(),
              const SizedBox(width: 8),
            ],
            _actionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 4),
            _buildIcon(36),
            const SizedBox(height: 6),
            _buildTypeLabel(),
            const SizedBox(height: 4),
            Text(
              item.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              item.targetPath,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.hotkeyVirtualKey != null) ...[
              const SizedBox(height: 4),
              _buildHotkeyBadge(),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.green, size: 22),
                  tooltip: '启动',
                  onPressed: () async {
                    final result = await LaunchService().launch(item);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.success
                            ? '正在启动 ${item.name}...'
                            : '启动失败: ${result.errorMessage ?? "未知错误"}'),
                        duration: Duration(seconds: result.success ? 1 : 3),
                      ),
                    );
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: '更多',
                  onSelected: (v) {
                    if (v == 'edit') _onEdit(context);
                    if (v == 'delete') _onDelete(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.play_arrow, color: Colors.green),
          tooltip: '启动',
          onPressed: () async {
            final result = await LaunchService().launch(item);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.success
                    ? '正在启动 ${item.name}...'
                    : '启动失败: ${result.errorMessage ?? "未知错误"}'),
                duration: Duration(seconds: result.success ? 1 : 3),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: '编辑',
          onPressed: () => _onEdit(context),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: '删除',
          onPressed: () => _onDelete(context),
        ),
      ],
    );
  }

  Widget _buildIcon(double size) {
    final icon = switch (item.type) {
      ItemType.executable => Icons.miscellaneous_services,
      ItemType.batScript => Icons.terminal,
      ItemType.file => Icons.description,
      ItemType.folder => Icons.folder,
      ItemType.system => Icons.power_settings_new,
      ItemType.command => Icons.terminal,
      ItemType.link => Icons.link,
    };
    final color = switch (item.type) {
      ItemType.executable => Colors.blue,
      ItemType.batScript => Colors.orange,
      ItemType.file => Colors.grey,
      ItemType.folder => Colors.amber,
      ItemType.system => Colors.red,
      ItemType.command => Colors.teal,
      ItemType.link => Colors.blue,
    };
    return Icon(icon, color: color, size: size);
  }

  Widget _buildTypeLabel() {
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, height: 1.3),
      ),
    );
  }

  Widget _buildHotkeyBadge() {
    final mod = <String>[];
    if (item.hotkeyModifiers != null) {
      if (item.hotkeyModifiers! & 0x01 != 0) mod.add('Alt');
      if (item.hotkeyModifiers! & 0x02 != 0) mod.add('Ctrl');
      if (item.hotkeyModifiers! & 0x04 != 0) mod.add('Shift');
      if (item.hotkeyModifiers! & 0x08 != 0) mod.add('Win');
    }
    final keyName = item.hotkeyVirtualKey != null
        ? _virtualKeyName(item.hotkeyVirtualKey!)
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Text(
        '${mod.join('+')}+$keyName',
        style: TextStyle(fontSize: 11, color: Colors.blue[800]),
      ),
    );
  }

  String _virtualKeyName(int key) {
    const keys = {
      0x08: 'Backspace',
      0x09: 'Tab',
      0x0D: 'Enter',
      0x1B: 'Esc',
      0x20: 'Space',
      0x21: 'PageUp',
      0x22: 'PageDown',
      0x23: 'End',
      0x24: 'Home',
      0x25: 'Left',
      0x26: 'Up',
      0x27: 'Right',
      0x28: 'Down',
      0x2D: 'Insert',
      0x2E: 'Delete',
      0x30: '0',
      0x31: '1',
      0x32: '2',
      0x33: '3',
      0x34: '4',
      0x35: '5',
      0x36: '6',
      0x37: '7',
      0x38: '8',
      0x39: '9',
      0x41: 'A',
      0x42: 'B',
      0x43: 'C',
      0x44: 'D',
      0x45: 'E',
      0x46: 'F',
      0x47: 'G',
      0x48: 'H',
      0x49: 'I',
      0x4A: 'J',
      0x4B: 'K',
      0x4C: 'L',
      0x4D: 'M',
      0x4E: 'N',
      0x4F: 'O',
      0x50: 'P',
      0x51: 'Q',
      0x52: 'R',
      0x53: 'S',
      0x54: 'T',
      0x55: 'U',
      0x56: 'V',
      0x57: 'W',
      0x58: 'X',
      0x59: 'Y',
      0x5A: 'Z',
      0x70: 'F1',
      0x71: 'F2',
      0x72: 'F3',
      0x73: 'F4',
      0x74: 'F5',
      0x75: 'F6',
      0x76: 'F7',
      0x77: 'F8',
      0x78: 'F9',
      0x79: 'F10',
      0x7A: 'F11',
      0x7B: 'F12',
    };
    return keys[key] ?? '0x${key.toRadixString(16).toUpperCase()}';
  }
}
