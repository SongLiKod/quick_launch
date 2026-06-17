import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/launch_item.dart';
import '../services/item_service.dart';
import '../services/hotkey_service.dart';
import '../services/group_service.dart';
import '../utils/scan_util.dart';

class ScanImportDialog extends StatefulWidget {
  const ScanImportDialog({super.key});

  @override
  State<ScanImportDialog> createState() => _ScanImportDialogState();
}

class _ScanImportDialogState extends State<ScanImportDialog> {
  final _scanFilter = ScanFilter();
  String? _folderPath;
  bool _isScanning = false;
  List<ScannedItem>? _scannedItems;
  String? _selectedGroupId;
  final _namePrefixController = TextEditingController();

  @override
  void dispose() {
    _namePrefixController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath();
    if (result != null) {
      setState(() => _folderPath = result);
    }
  }

  Future<void> _startScan() async {
    if (_folderPath == null || _folderPath!.isEmpty) return;

    setState(() {
      _isScanning = true;
      _scannedItems = null;
    });

    final items = await ScanUtil.scanDirectory(_folderPath!, _scanFilter);

    setState(() {
      _scannedItems = items;
      _isScanning = false;
    });
  }

  void _toggleSelectAll(bool? selected) {
    if (_scannedItems == null) return;
    setState(() {
      for (final item in _scannedItems!) {
        item.selected = selected ?? true;
      }
    });
  }

  int get _selectedCount =>
      _scannedItems?.where((item) => item.selected).length ?? 0;

  Future<void> _import() async {
    if (_scannedItems == null || _selectedCount == 0) return;

    final prefix = _namePrefixController.text.trim();
    final newItems = <LaunchItem>[];

    for (final scanned in _scannedItems!) {
      if (!scanned.selected) continue;

      final name = prefix.isEmpty
          ? scanned.name
          : '$prefix${scanned.name}';

      newItems.add(LaunchItem(
        id: const Uuid().v4(),
        name: name,
        targetPath: scanned.targetPath,
        type: scanned.type,
        groupId: _selectedGroupId,
      ));
    }

    final service = ItemService();
    await service.addItems(newItems);

    // 注册快捷键（如果有）
    for (final item in newItems) {
      if (item.hotkeyVirtualKey != null) {
        HotkeyService().registerItemHotkey(item);
      }
    }

    if (mounted) {
      Navigator.of(context).pop(newItems.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = GroupService().groups.value;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.manage_search, size: 22),
          const SizedBox(width: 8),
          const Text('批量扫描导入'),
          const Spacer(),
          if (_scannedItems != null)
            Text(
              '${_scannedItems!.length} 项',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 文件夹路径 ──
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: '目标文件夹',
                        hintText: '选择要扫描的文件夹',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: _folderPath != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () =>
                                    setState(() => _folderPath = null),
                              )
                            : null,
                      ),
                      controller: TextEditingController(text: _folderPath ?? ''),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('浏览'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── 文件类型过滤 ──
              Text('文件类型', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('应用程序 (.exe)'),
                    selected: _scanFilter.includeExe,
                    onSelected: (v) => setState(() => _scanFilter.includeExe = v),
                  ),
                  FilterChip(
                    label: const Text('脚本 (.bat/.cmd)'),
                    selected: _scanFilter.includeBat,
                    onSelected: (v) => setState(() => _scanFilter.includeBat = v),
                  ),
                  FilterChip(
                    label: const Text('文件夹'),
                    selected: _scanFilter.includeFolder,
                    onSelected: (v) => setState(() => _scanFilter.includeFolder = v),
                  ),
                ],
              ),

              // ── 自定义扩展名 ──
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  labelText: '自定义扩展名（分号分隔）',
                  hintText: '.pdf;.docx;.jpg',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  _scanFilter.customExtensions = v
                      .split(';')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                },
              ),
              const SizedBox(height: 8),

              // ── 递归选项 ──
              Row(
                children: [
                  const Text('包含子文件夹'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _scanFilter.includeSubfolders,
                    onChanged: (v) =>
                        setState(() => _scanFilter.includeSubfolders = v),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _folderPath == null ? null : _startScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(_isScanning ? '扫描中...' : '开始扫描'),
                  ),
                ],
              ),

              // ── 扫描结果 ──
              if (_scannedItems != null) ...[
                const Divider(height: 24),
                if (_scannedItems!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('未找到匹配的文件',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Checkbox(
                        value: _scannedItems!.every((i) => i.selected),
                        tristate: true,
                        onChanged: _toggleSelectAll,
                      ),
                      const Text('全选'),
                      const Spacer(),
                      Text(
                        '已选 $_selectedCount 项',
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _scannedItems!.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
                      itemBuilder: (_, i) {
                        final item = _scannedItems![i];
                        final typeLabel = switch (item.type) {
                          ItemType.executable => '应用',
                          ItemType.batScript => '脚本',
                          ItemType.file => '文件',
                          ItemType.folder => '文件夹',
                          _ => '',
                        };
                        return InkWell(
                          onTap: () =>
                              setState(() => item.selected = !item.selected),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: item.selected,
                                  onChanged: (v) => setState(
                                      () => item.selected = v ?? false),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: typeLabel == '应用'
                                        ? Colors.blue.withValues(alpha: 0.1)
                                        : typeLabel == '脚本'
                                            ? Colors.orange
                                                .withValues(alpha: 0.1)
                                            : Colors.grey.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(typeLabel,
                                      style: const TextStyle(fontSize: 10)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        item.targetPath,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],

              // ── 导入选项 ──
              if (_scannedItems != null && _scannedItems!.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    const Text('目标分组: '),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 180,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedGroupId,
                            isExpanded: true,
                            hint: const Text('无分组',
                                style: TextStyle(fontSize: 13)),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('无分组',
                                    style: TextStyle(fontSize: 13)),
                              ),
                              ...groups.map((g) => DropdownMenuItem(
                                    value: g.id,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Color(g.colorValue),
                                          radius: 6,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(g.name,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  )),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedGroupId = v),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _namePrefixController,
                        decoration: const InputDecoration(
                          labelText: '名称前缀（可选）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (_scannedItems != null && _selectedCount > 0)
          FilledButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.download, size: 18),
            label: Text('导入 $_selectedCount 项'),
          ),
      ],
    );
  }
}
