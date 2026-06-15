import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/item_group.dart';
import '../services/group_service.dart';

class GroupManageDialog extends StatefulWidget {
  const GroupManageDialog({super.key});

  @override
  State<GroupManageDialog> createState() => _GroupManageDialogState();
}

class _GroupManageDialogState extends State<GroupManageDialog> {
  final _service = GroupService();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理分组'),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<List<ItemGroup>>(
          valueListenable: _service.groups,
          builder: (_, groups, _) {
            if (groups.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('暂无分组，点击下方按钮添加',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: groups.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final group = groups[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Color(group.colorValue),
                    radius: 14,
                    child: Text(
                      group.name.isNotEmpty
                          ? group.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(group.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: '重命名',
                        onPressed: () => _editGroup(context, group),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        tooltip: '删除',
                        onPressed: () => _deleteGroup(context, group),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _addGroup(context),
          child: const Text('添加分组'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  void _addGroup(BuildContext context) {
    _showNameDialog(
      context,
      title: '添加分组',
      onConfirm: (name) async {
        if (name.trim().isEmpty) return;
        final group = ItemGroup(
          id: const Uuid().v4(),
          name: name.trim(),
          colorValue: _nextColor(),
          sortOrder: _service.groups.value.length,
        );
        await _service.addGroup(group);
      },
    );
  }

  void _editGroup(BuildContext context, ItemGroup group) {
    _showNameDialog(
      context,
      title: '重命名分组',
      initial: group.name,
      onConfirm: (name) async {
        if (name.trim().isEmpty) return;
        group.name = name.trim();
        await _service.updateGroup(group);
      },
    );
  }

  void _deleteGroup(BuildContext context, ItemGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定要删除"${group.name}"吗？\n属于该分组的启动项将变为"未分组"。'),
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
    if (confirmed == true) {
      await _service.deleteGroup(group.id);
    }
  }

  void _showNameDialog(
    BuildContext context, {
    required String title,
    String initial = '',
    required void Function(String name) onConfirm,
  }) {
    final controller = TextEditingController(text: initial);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            onConfirm(controller.text);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onConfirm(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  int _nextColor() {
    final used = _service.groups.value
        .map((g) => g.colorValue)
        .toSet();
    for (final c in GroupService.presetColors) {
      if (!used.contains(c)) return c;
    }
    return GroupService.presetColors[
        _service.groups.value.length % GroupService.presetColors.length];
  }
}
