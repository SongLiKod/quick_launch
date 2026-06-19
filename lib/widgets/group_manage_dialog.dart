import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/item_group.dart';
import '../services/group_service.dart';
import '../services/hotkey_service.dart';
import '../pages/settings_page.dart';

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
                  child: Text(
                    '暂无分组，点击下方按钮添加',
                    style: TextStyle(color: Colors.grey),
                  ),
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
                      group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(group.name),
                  subtitle: group.hasGroupHotkey
                      ? Text(
                          formatHotkeyLabel(
                            group.groupHotkeyModifiers,
                            group.groupHotkeyVirtualKey,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          group.hasGroupHotkey
                              ? Icons.keyboard
                              : Icons.keyboard_outlined,
                          size: 18,
                          color: group.hasGroupHotkey ? Colors.blue : null,
                        ),
                        tooltip: group.hasGroupHotkey ? '修改分组快捷键' : '设置分组快捷键',
                        onPressed: () => _editGroupHotkey(context, group),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: '重命名',
                        onPressed: () => _editGroup(context, group),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
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
    final nameController = TextEditingController(text: group.name);
    int selectedColor = group.colorValue;
    bool useCustomColor = false;
    Color customColor = Color(group.colorValue);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑分组'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '分组名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '选择颜色',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...GroupService.presetColors.map((colorValue) {
                      final isSelected =
                          !useCustomColor && selectedColor == colorValue;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = colorValue;
                            useCustomColor = false;
                          });
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(colorValue),
                            borderRadius: BorderRadius.circular(6),
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Color(colorValue),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      );
                    }),
                    // 自定义颜色按钮
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDialog<Color>(
                          context: ctx,
                          builder: (colorCtx) => _SimpleColorPicker(
                            initialColor: useCustomColor
                                ? customColor
                                : Color(selectedColor),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            customColor = picked;
                            selectedColor = picked.toARGB32();
                            useCustomColor = true;
                          });
                        }
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: useCustomColor
                              ? customColor
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(6),
                          border: useCustomColor
                              ? Border.all(color: Colors.white, width: 3)
                              : Border.all(color: Colors.grey[400]!),
                          boxShadow: useCustomColor
                              ? [BoxShadow(color: customColor, blurRadius: 8)]
                              : null,
                        ),
                        child: const Icon(
                          Icons.colorize,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                group.name = name;
                group.colorValue = selectedColor;
                await _service.updateGroup(group);
                Navigator.of(ctx).pop();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _editGroupHotkey(BuildContext context, ItemGroup group) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('分组快捷键 - ${group.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置全局快捷键，按 Alt+字母/数字 组合触发此分组的选择面板'),
            const SizedBox(height: 8),
            Text(
              '格式: Ctrl+Alt+A\n例如: Ctrl+Shift+1, Ctrl+Alt+S, Win+G',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '快捷键',
                hintText: group.hasGroupHotkey
                    ? formatHotkeyLabel(
                        group.groupHotkeyModifiers,
                        group.groupHotkeyVirtualKey,
                      )
                    : 'Ctrl+Shift+1',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          if (group.hasGroupHotkey)
            TextButton(
              onPressed: () async {
                HotkeyService().unregisterGroupHotkey(group.id);
                group.groupHotkeyModifiers = null;
                group.groupHotkeyVirtualKey = null;
                await _service.updateGroup(group);
                Navigator.of(ctx).pop();
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已清除分组快捷键')));
              },
              child: const Text('清除', style: TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              final result = parseHotkeyText(text);
              if (result == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('无效格式，请使用 Ctrl+Alt+A 格式')),
                );
                return;
              }
              final (modifiers, vk) = result;

              // 检测冲突
              final conflict = HotkeyService().findGroupConflict(
                modifiers,
                vk,
                excludeGroupId: group.id,
              );
              if (conflict != null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('快捷键冲突: "$conflict" 已占用')),
                );
                return;
              }

              // 先注销旧的
              if (group.hasGroupHotkey) {
                HotkeyService().unregisterGroupHotkey(group.id);
              }
              // 设置新热键
              group.groupHotkeyModifiers = modifiers;
              group.groupHotkeyVirtualKey = vk;
              await _service.updateGroup(group);
              Navigator.of(ctx).pop();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('分组快捷键已设为 ${formatHotkeyLabel(modifiers, vk)}'),
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
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
    final used = _service.groups.value.map((g) => g.colorValue).toSet();
    for (final c in GroupService.presetColors) {
      if (!used.contains(c)) return c;
    }
    return GroupService.presetColors[_service.groups.value.length %
        GroupService.presetColors.length];
  }
}

/// A simple color picker dialog with HSV-style sliders
class _SimpleColorPicker extends StatefulWidget {
  final Color initialColor;
  const _SimpleColorPicker({required this.initialColor});

  @override
  State<_SimpleColorPicker> createState() => _SimpleColorPickerState();
}

class _SimpleColorPickerState extends State<_SimpleColorPicker> {
  late double _hue, _saturation, _brightness;
  late Color _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialColor;
    final hsv = HSVColor.fromColor(_current);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _brightness = hsv.value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color preview
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: _current.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Hue slider
            _buildSlider('色相', _hue, 360, (v) {
              setState(() {
                _hue = v;
                _current = HSVColor.fromAHSV(
                  1,
                  _hue,
                  _saturation,
                  _brightness,
                ).toColor();
              });
            }, _current),
            const SizedBox(height: 8),
            // Saturation slider
            _buildSlider('饱和度', _saturation, 1, (v) {
              setState(() {
                _saturation = v;
                _current = HSVColor.fromAHSV(
                  1,
                  _hue,
                  _saturation,
                  _brightness,
                ).toColor();
              });
            }, _current),
            const SizedBox(height: 8),
            // Brightness slider
            _buildSlider('亮度', _brightness, 1, (v) {
              setState(() {
                _brightness = v;
                _current = HSVColor.fromAHSV(
                  1,
                  _hue,
                  _saturation,
                  _brightness,
                ).toColor();
              });
            }, _current),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_current),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
    Color trackColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            activeTrackColor: trackColor,
            inactiveTrackColor: trackColor.withValues(alpha: 0.2),
          ),
          child: Slider(value: value, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
