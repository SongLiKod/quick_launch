import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/launch_item.dart';
import '../models/item_group.dart';
import '../services/item_service.dart';
import '../services/launch_service.dart';

/// 分组快捷键选中弹窗 — 按分组快捷键后弹出，按 A-Z 字母键快速启动项
class GroupHotkeyOverlay extends StatefulWidget {
  final ItemGroup group;

  const GroupHotkeyOverlay({super.key, required this.group});

  /// 展示分组快捷键覆盖层
  static void show(BuildContext context, ItemGroup group) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) => GroupHotkeyOverlay(group: group),
    );
  }

  @override
  State<GroupHotkeyOverlay> createState() => _GroupHotkeyOverlayState();
}

class _GroupHotkeyOverlayState extends State<GroupHotkeyOverlay> {
  int _selectedIndex = 0;
  final Set<int> _checkedIndexes = {};
  late final List<LaunchItem> _items;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _items = ItemService()
        .items
        .value
        .where((item) => item.groupId == widget.group.id)
        .toList();
    _focusNode = FocusNode();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String _letterFor(int index) {
    if (index < 26) return String.fromCharCode(65 + index); // A-Z
    return '?';
  }

  void _launchItem(LaunchItem item) {
    LaunchService().launch(item);
  }

  void _launchCheckedItems() {
    for (final i in _checkedIndexes) {
      if (i >= 0 && i < _items.length) {
        LaunchService().launch(_items[i]);
      }
    }
  }

  void _toggleCheck(int index) {
    setState(() {
      if (_checkedIndexes.contains(index)) {
        _checkedIndexes.remove(index);
      } else {
        _checkedIndexes.add(index);
      }
    });
  }

  bool get _hasChecked => _checkedIndexes.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          // Escape to close
          if (key == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          // Enter to launch selected item (single)
          if (key == LogicalKeyboardKey.enter &&
              _selectedIndex >= 0 &&
              _selectedIndex < _items.length) {
            _launchItem(_items[_selectedIndex]);
            return KeyEventResult.handled;
          }
          // Space to toggle checkbox
          if (key == LogicalKeyboardKey.space &&
              _selectedIndex >= 0 &&
              _selectedIndex < _items.length) {
            _toggleCheck(_selectedIndex);
            return KeyEventResult.handled;
          }
          // Ctrl+A to select all
          if (key == LogicalKeyboardKey.keyA &&
              (event is KeyDownEvent) &&
              HardwareKeyboard.instance.isControlPressed) {
            setState(() {
              if (_checkedIndexes.length == _items.length) {
                _checkedIndexes.clear();
              } else {
                _checkedIndexes.addAll(List.generate(_items.length, (i) => i));
              }
            });
            return KeyEventResult.handled;
          }
          // Arrow keys to navigate
          if (key == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _selectedIndex = (_selectedIndex + 1) % _items.length;
            });
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            setState(() {
              _selectedIndex =
                  (_selectedIndex - 1 + _items.length) % _items.length;
            });
            return KeyEventResult.handled;
          }
          // A-Z to launch by letter
          if (key.keyLabel.length == 1) {
            final char = key.keyLabel.toUpperCase();
            final code = char.codeUnitAt(0);
            if (code >= 65 && code <= 90) {
              final idx = code - 65;
              if (idx >= 0 && idx < _items.length) {
                _launchItem(_items[idx]);
                return KeyEventResult.handled;
              }
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: theme.dialogTheme.backgroundColor ??
                    theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      color: Color(widget.group.colorValue)
                          .withValues(alpha: 0.1),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Color(widget.group.colorValue),
                          radius: 16,
                          child: Text(
                            widget.group.name[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.group.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${_items.length}项',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  // 列表
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('该分组暂无启动项',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...List.generate(_items.length, (i) {
                      final item = _items[i];
                      final selected = i == _selectedIndex;
                      final checked = _checkedIndexes.contains(i);
                      return InkWell(
                        onTap: () => _launchItem(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.4)
                                : null,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.dividerColor
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // 多选框
                              GestureDetector(
                                onTap: () => _toggleCheck(i),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    checked
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 22,
                                    color: checked
                                        ? Color(widget.group.colorValue)
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              // 字母快捷键标识
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: checked
                                      ? Color(widget.group.colorValue)
                                      : selected
                                          ? theme.colorScheme.primary
                                          : Colors.grey[400],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _letterFor(i),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // 图标
                              _buildIcon(item),
                              const SizedBox(width: 8),
                              // 名称和路径
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(item.targetPath,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              // 类型标签
                              _buildTypeLabel(item),
                            ],
                          ),
                        ),
                      );
                    }),
                  // 底部提示
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(bottom: Radius.circular(16)),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '按 A-${_letterFor(_items.length - 1)} 启动或Enter启动选中项  ·  空格选中  ·  方向键切换  ·  Esc 关闭',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ),
                        if (_hasChecked)
                          FilledButton.tonalIcon(
                            onPressed: _launchCheckedItems,
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: Text('启动所选 (${_checkedIndexes.length})',
                                style: const TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
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

  Widget _buildIcon(LaunchItem item) {
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
}
