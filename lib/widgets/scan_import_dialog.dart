import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/launch_item.dart';
import '../models/item_group.dart';
import '../services/item_service.dart';
import '../services/hotkey_service.dart';
import '../services/group_service.dart';
import '../utils/scan_util.dart';

/// 批量扫描导入对话框
/// 支持两种扫描模式：文件夹扫描 / 已安装软件扫描
class ScanImportDialog extends StatefulWidget {
  const ScanImportDialog({super.key});

  @override
  State<ScanImportDialog> createState() => _ScanImportDialogState();
}

class _ScanImportDialogState extends State<ScanImportDialog> {
  // 当前模式: 0=文件夹扫描, 1=已安装软件扫描
  int _tabIndex = 0;

  // ── 文件夹扫描参数 ──
  final _scanFilter = ScanFilter();
  String? _folderPath;

  // ── 通用状态 ──
  bool _isScanning = false;
  bool _configExpanded = true;
  List<ScannedItem>? _scannedItems;
  String? _selectedGroupId;
  final _namePrefixController = TextEditingController();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// 根据搜索关键词过滤后的可见项
  List<ScannedItem> get _filteredItems {
    if (_scannedItems == null || _searchQuery.isEmpty) {
      return _scannedItems ?? [];
    }
    final q = _searchQuery.toLowerCase();
    return _scannedItems!
        .where((item) =>
            item.name.toLowerCase().contains(q) ||
            item.targetPath.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _namePrefixController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── 文件夹扫描 ──

  Future<void> _pickFolder() async {
    final result = await FilePicker.getDirectoryPath();
    if (result != null) {
      setState(() => _folderPath = result);
    }
  }

  Future<void> _startFolderScan() async {
    if (_folderPath == null || _folderPath!.isEmpty) return;

    setState(() {
      _isScanning = true;
      _scannedItems = null;
    });

    final items = await ScanUtil.scanDirectory(_folderPath!, _scanFilter);

    if (mounted) {
      setState(() {
        _scannedItems = items;
        _isScanning = false;
      });
    }
  }

  // ── 已安装软件扫描 ──

  Future<void> _startInstalledScan() async {
    setState(() {
      _isScanning = true;
      _scannedItems = null;
    });

    final items = await ScanUtil.scanInstalledSoftware();

    if (mounted) {
      setState(() {
        _scannedItems = items;
        _isScanning = false;
      });
    }
  }

  // ── 通用 ──

  void _toggleSelectAll(bool? selected) {
    if (_scannedItems == null) return;
    final visible = _filteredItems;
    if (visible.isEmpty) return;
    // 如果所有可见项都已选中，则取消全选；否则全选
    final allSelected = visible.every((item) => item.selected);
    setState(() {
      for (final item in visible) {
        item.selected = !allSelected;
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

      final name =
          prefix.isEmpty ? scanned.name : '$prefix${scanned.name}';

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
        width: 600,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Tab 切换 ──
              Row(
                children: [
                  _buildTab('📁  文件夹扫描', 0),
                  const SizedBox(width: 8),
                  _buildTab('💻  已安装软件', 1),
                  const Spacer(),
                  // 扫描后有结果时允许折叠/展开设置区
                  if (_scannedItems != null && _scannedItems!.isNotEmpty)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          _configExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _configExpanded = !_configExpanded),
                        tooltip: _configExpanded ? '收起设置' : '展开设置',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Tab 内容（可折叠）──
              if (_configExpanded) ...[
                if (_tabIndex == 0) _buildFolderScanTab(theme),
                if (_tabIndex == 1) _buildInstalledScanTab(theme),
                const SizedBox(height: 12),
              ],

              // ── 扫描结果 ──
              if (_scannedItems != null) _buildResultSection(theme, groups),
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

  Widget _buildTab(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tabIndex = index;
          _scannedItems = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  // ── 文件夹扫描 UI ──

  Widget _buildFolderScanTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                controller:
                    TextEditingController(text: _folderPath ?? ''),
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
        const SizedBox(height: 12),
        Text('文件类型',
            style:
                TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('应用程序 (.exe)'),
              selected: _scanFilter.includeExe,
              onSelected: (v) =>
                  setState(() => _scanFilter.includeExe = v),
            ),
            FilterChip(
              label: const Text('脚本 (.bat/.cmd)'),
              selected: _scanFilter.includeBat,
              onSelected: (v) =>
                  setState(() => _scanFilter.includeBat = v),
            ),
            FilterChip(
              label: const Text('文件夹'),
              selected: _scanFilter.includeFolder,
              onSelected: (v) =>
                  setState(() => _scanFilter.includeFolder = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            labelText: '自定义扩展名（分号分隔）',
            hintText: '.pdf;.docx;.jpg',
            border: OutlineInputBorder(),
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
              onPressed: _folderPath == null ? null : _startFolderScan,
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
      ],
    );
  }

  // ── 已安装软件扫描 UI ──

  Widget _buildInstalledScanTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '扫描系统已安装的应用程序',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '将从开始菜单、桌面快捷方式和注册表中\n收集已安装的应用程序',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isScanning ? null : _startInstalledScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.computer, size: 18),
                label: Text(_isScanning ? '扫描中...' : '开始扫描'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '提示：首次扫描速度较慢，请耐心等待。扫描结果仅包含带 .exe 目标路径的有效快捷方式。',
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }

  // ── 结果区域 ──

  Widget _buildResultSection(
      ThemeData theme, List<ItemGroup> groups) {
    if (_scannedItems!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('未找到匹配的项目',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        // ── 搜索框 ──
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索过滤结果...',
            prefixIcon: const Icon(Icons.search, size: 18),
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      _searchQuery = '';
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: _filteredItems.every((i) => i.selected),
              onChanged: _toggleSelectAll,
            ),
            const Text('全选'),
            const Spacer(),
            Text(
              '已选 $_selectedCount / ${_scannedItems!.length} 项',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.primary),
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 360),
          decoration: BoxDecoration(
            border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _filteredItems.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('无匹配项',
                      style: TextStyle(color: Colors.grey)),
                ))
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _filteredItems.length,
            separatorBuilder: (_, _) => Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.2)),
            itemBuilder: (_, i) {
              final item = _filteredItems[i];
              final typeLabel = switch (item.type) {
                ItemType.executable => '应用',
                ItemType.batScript => '脚本',
                ItemType.file => '文件',
                ItemType.folder => '文件夹',
                _ => '',
              };
              return InkWell(
                onTap: () => setState(
                    () => item.selected = !item.selected),
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
                                  : Colors.grey
                                      .withValues(alpha: 0.1),
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
        const Divider(height: 16),
        // ── 导入选项 ──
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
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
    );
  }
}
