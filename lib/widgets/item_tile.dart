import 'package:flutter/material.dart';
import '../models/launch_item.dart';
import '../services/hotkey_service.dart';
import '../services/item_service.dart';
import '../services/launch_service.dart';
import 'add_item_dialog.dart';

class ItemTile extends StatefulWidget {
  final LaunchItem item;
  final int? index;
  final bool isGridMode;
  final String? groupName;
  final bool selectMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelect;

  const ItemTile({
    super.key,
    required this.item,
    this.index,
    this.isGridMode = false,
    this.groupName,
    this.selectMode = false,
    this.isSelected = false,
    this.onSelect,
  });

  @override
  State<ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<ItemTile> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnim;

  late AnimationController _shakeController;
  late Animation<Offset> _shakeAnim;
  final ValueNotifier<Color?> _borderColor = ValueNotifier(null);

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.92), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<Offset>([
      TweenSequenceItem(
          tween: Tween(begin: Offset.zero, end: const Offset(-4, 0)), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: const Offset(-4, 0), end: const Offset(4, 0)), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: const Offset(4, 0), end: const Offset(-3, 0)), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: const Offset(-3, 0), end: const Offset(3, 0)), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: const Offset(3, 0), end: const Offset(-1, 0)), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: const Offset(-1, 0), end: Offset.zero), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shakeController.dispose();
    _borderColor.dispose();
    super.dispose();
  }

  void _onLaunch(BuildContext context) async {
    final result = await LaunchService().launch(widget.item);
    if (!mounted) return;

    if (result.success) {
      _pulseController.forward().then((_) => _pulseController.reset());
    } else {
      _borderColor.value = Colors.red;
      _shakeController.forward().then((_) {
        _borderColor.value = null;
        _shakeController.reset();
      });
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? '正在启动 ${widget.item.name}...'
            : '启动失败: ${result.errorMessage ?? "未知错误"}'),
        duration: Duration(seconds: result.success ? 1 : 3),
      ),
    );
  }

  void _onEdit(BuildContext context) async {
    final result = await showDialog<LaunchItem>(
      context: context,
      builder: (ctx) => AddItemDialog(item: widget.item),
    );
    if (result == null) return;

    // 原快捷键变了 → 先注销旧的
    if (widget.item.hotkeyVirtualKey != null) {
      HotkeyService().unregisterItemHotkey(widget.item);
    }

    // 更新数据
    ItemService().updateItem(result);

    // 新快捷键不为空 → 注册新的
    if (result.hotkeyVirtualKey != null) {
      HotkeyService().registerItemHotkey(result);
    }
  }

  void _onDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除"${widget.item.name}"？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (widget.item.hotkeyVirtualKey != null) {
                HotkeyService().unregisterItemHotkey(widget.item);
              }
              ItemService().removeItem(widget.item.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _onKillProcess(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('结束进程'),
        content: Text('确定结束 "${widget.item.name}" 的进程？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('结束', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final killed = await LaunchService().killProcess(widget.item.name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(killed ? '已结束 "${widget.item.name}" 的进程' : '结束进程失败'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGridMode) return _buildGridTile(context);
    return _buildListTile(context);
  }

  Widget _buildListTile(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _shakeController, _borderColor]),
      builder: (context, _) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Transform.translate(
            offset: _shakeAnim.value,
            child: ValueListenableBuilder<Color?>(
              valueListenable: _borderColor,
              builder: (_, borderColor, child) {
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: borderColor != null
                      ? RoundedRectangleBorder(
                          side: BorderSide(color: borderColor, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        if (widget.selectMode)
                          Checkbox(
                            value: widget.isSelected,
                            onChanged: (v) => widget.onSelect?.call(v ?? false),
                          ),
                        if (!widget.selectMode && widget.index != null)
                          ReorderableDragStartListener(
                            index: widget.index!,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.drag_handle, color: Colors.grey),
                            ),
                          ),
                        _buildIcon(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _buildTypeLabel(),
                                  if (_isStale()) ...[
                                    const SizedBox(width: 4),
                                    _buildStaleBadge(),
                                  ],
                                  if (widget.groupName != null) ...[
                                    const SizedBox(width: 4),
                                    _buildGroupBadge(),
                                  ],
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.item.name,
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
                                widget.item.targetPath,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.item.aliases.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: widget.item.aliases.map((a) => Container(
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
                        if (widget.item.hotkeyVirtualKey != null) ...[
                          _buildHotkeyBadge(),
                          const SizedBox(width: 8),
                        ],
                        if (!widget.selectMode) ...[
                          IconButton(
                            icon: const Icon(Icons.play_arrow, color: Colors.green),
                            tooltip: '启动',
                            onPressed: () => _onLaunch(context),
                          ),
                          ValueListenableBuilder<List<ProcessInfo>>(
                            valueListenable: LaunchService().runningProcesses,
                            builder: (_, processes, _) {
                              final isRunning = processes.any(
                                  (p) => p.itemName == widget.item.name);
                              return isRunning
                                  ? IconButton(
                                      icon: const Icon(Icons.stop_circle_outlined,
                                          color: Colors.red),
                                      tooltip: '结束进程',
                                      onPressed: () => _onKillProcess(context),
                                    )
                                  : const SizedBox.shrink();
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
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridTile(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _shakeController, _borderColor]),
      builder: (context, _) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Transform.translate(
            offset: _shakeAnim.value,
            child: ValueListenableBuilder<Color?>(
              valueListenable: _borderColor,
              builder: (_, borderColor, child) {
                return Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: borderColor != null
                      ? RoundedRectangleBorder(
                          side: BorderSide(color: borderColor, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: InkWell(
                    onTap: widget.selectMode
                        ? () => widget.onSelect?.call(!widget.isSelected)
                        : () => _onLaunch(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Row(
                        children: [
                          if (widget.selectMode)
                            Checkbox(
                              value: widget.isSelected,
                              onChanged: (v) => widget.onSelect?.call(v ?? false),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          _buildIcon(size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Row(
                                  children: [
                                    _buildTypeLabel(),
                                    if (_isStale()) ...[
                                      const SizedBox(width: 4),
                                      _buildStaleBadge(),
                                    ],
                                    if (widget.groupName != null) ...[
                                      const SizedBox(width: 4),
                                      _buildGroupBadge(),
                                    ],
                                    if (widget.item.hotkeyVirtualKey != null) ...[
                                      const SizedBox(width: 4),
                                      _buildHotkeyBadge(),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          _buildMiniIconButton(
                            icon: Icons.play_arrow,
                            color: Colors.green,
                            tooltip: '启动',
                            onPressed: () => _onLaunch(context),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onSelected: (action) {
                              if (action == 'edit') _onEdit(context);
                              if (action == 'delete') _onDelete(context);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('编辑'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('删除', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    String? tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      color: color,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildIcon({double size = 24}) {
    switch (widget.item.type) {
      case ItemType.executable:
        return Icon(Icons.miscellaneous_services, color: Colors.blue, size: size);
      case ItemType.batScript:
        return Icon(Icons.terminal, color: Colors.orange, size: size);
      case ItemType.file:
        return Icon(Icons.description, color: Colors.grey, size: size);
      case ItemType.folder:
        return Icon(Icons.folder, color: Colors.amber, size: size);
      case ItemType.system:
        return Icon(Icons.power_settings_new, color: Colors.red, size: size);
      case ItemType.command:
        return Icon(Icons.terminal, color: Colors.teal, size: size);
      case ItemType.link:
        return Icon(Icons.link, color: Colors.blue, size: size);
    }
  }

  Widget _buildTypeLabel() {
    final (label, color) = switch (widget.item.type) {
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

  Widget _buildGroupBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Text(
        widget.groupName!,
        style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.3),
      ),
    );
  }

  Widget _buildHotkeyBadge() {
    final mod = <String>[];
    if (widget.item.hotkeyModifiers != null) {
      if (widget.item.hotkeyModifiers! & 0x01 != 0) mod.add('Alt');
      if (widget.item.hotkeyModifiers! & 0x02 != 0) mod.add('Ctrl');
      if (widget.item.hotkeyModifiers! & 0x04 != 0) mod.add('Shift');
      if (widget.item.hotkeyModifiers! & 0x08 != 0) mod.add('Win');
    }
    final keyName = widget.item.hotkeyVirtualKey != null
        ? _virtualKeyName(widget.item.hotkeyVirtualKey!)
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

  bool _isStale() {
    if (widget.item.lastLaunchAt == null) return false;
    final daysSinceLastUse = DateTime.now().difference(widget.item.lastLaunchAt!).inDays;
    return daysSinceLastUse >= 30;
  }

  Widget _buildStaleBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Text(
        widget.item.lastLaunchAt == null ? '未使用' : '30天未使用',
        style: const TextStyle(fontSize: 10, color: Colors.orange, height: 1.3),
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
