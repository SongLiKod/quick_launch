import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:win32/win32.dart';
import '../services/settings_service.dart';
import '../services/item_service.dart';
import '../services/hotkey_service.dart';
import '../services/launch_service.dart';
import '../services/update_service.dart';
import 'logs_page.dart';

/// 将快捷键修饰键和虚拟键码转为可读文本
String formatHotkeyLabel(int? modifiers, int? virtualKey) {
  if (modifiers == null || virtualKey == null) return '未设置';
  final parts = <String>[];
  if (modifiers & 0x01 != 0) parts.add('Alt');
  if (modifiers & 0x02 != 0) parts.add('Ctrl');
  if (modifiers & 0x04 != 0) parts.add('Shift');
  if (modifiers & 0x08 != 0) parts.add('Win');
  parts.add(_vkName(virtualKey));
  return parts.join('+');
}

String _vkName(int key) {
  const map = <int, String>{
    0x08: 'Backspace', 0x09: 'Tab', 0x0D: 'Enter', 0x1B: 'Esc',
    0x20: 'Space', 0x21: 'PageUp', 0x22: 'PageDown', 0x23: 'End',
    0x24: 'Home', 0x25: 'Left', 0x26: 'Up', 0x27: 'Right', 0x28: 'Down',
    0x2D: 'Insert', 0x2E: 'Delete',
    0x30: '0', 0x31: '1', 0x32: '2', 0x33: '3', 0x34: '4',
    0x35: '5', 0x36: '6', 0x37: '7', 0x38: '8', 0x39: '9',
    0x41: 'A', 0x42: 'B', 0x43: 'C', 0x44: 'D', 0x45: 'E',
    0x46: 'F', 0x47: 'G', 0x48: 'H', 0x49: 'I', 0x4A: 'J',
    0x4B: 'K', 0x4C: 'L', 0x4D: 'M', 0x4E: 'N', 0x4F: 'O',
    0x50: 'P', 0x51: 'Q', 0x52: 'R', 0x53: 'S', 0x54: 'T',
    0x55: 'U', 0x56: 'V', 0x57: 'W', 0x58: 'X', 0x59: 'Y', 0x5A: 'Z',
    0x70: 'F1', 0x71: 'F2', 0x72: 'F3', 0x73: 'F4', 0x74: 'F5',
    0x75: 'F6', 0x76: 'F7', 0x77: 'F8', 0x78: 'F9', 0x79: 'F10',
    0x7A: 'F11', 0x7B: 'F12',
  };
  return map[key] ?? '0x${key.toRadixString(16).toUpperCase()}';
}

/// 解析用户输入的快捷键文本（如 Ctrl+Alt+A），返回 (modifiers, virtualKey)
(int, int)? parseHotkeyText(String text) {
  final parts = text.split('+').map((s) => s.trim()).toList();
  if (parts.length < 2) return null;
  int modifiers = 0;
  String? keyPart;

  for (int i = 0; i < parts.length; i++) {
    final lower = parts[i].toLowerCase();
    if (['ctrl', 'control', 'alt', 'shift', 'win', 'windows', 'meta']
        .contains(lower)) {
      switch (lower) {
        case 'ctrl':
        case 'control':
          modifiers |= 0x02;
          break;
        case 'alt':
          modifiers |= 0x01;
          break;
        case 'shift':
          modifiers |= 0x04;
          break;
        case 'win':
        case 'windows':
        case 'meta':
          modifiers |= 0x08;
          break;
      }
    } else {
      if (i != parts.length - 1) return null;
      keyPart = parts[i];
    }
  }
  if (modifiers == 0 || keyPart == null || keyPart.isEmpty) return null;
  final vk = _textToVk(keyPart);
  if (vk == null) return null;
  return (modifiers, vk);
}

int? _textToVk(String key) {
  final upper = key.toUpperCase();
  if (upper.length == 1 && upper.codeUnitAt(0) >= 0x41 &&
      upper.codeUnitAt(0) <= 0x5A) {
    return upper.codeUnitAt(0);
  }
  if (upper.length == 1 && upper.codeUnitAt(0) >= 0x30 &&
      upper.codeUnitAt(0) <= 0x39) {
    return upper.codeUnitAt(0);
  }
  const map = <String, int>{
    'F1': 0x70, 'F2': 0x71, 'F3': 0x72, 'F4': 0x73, 'F5': 0x74,
    'F6': 0x75, 'F7': 0x76, 'F8': 0x77, 'F9': 0x78, 'F10': 0x79,
    'F11': 0x7A, 'F12': 0x7B,
    'SPACE': 0x20, 'ENTER': 0x0D, 'RETURN': 0x0D, 'TAB': 0x09,
    'ESC': 0x1B, 'ESCAPE': 0x1B,
    'BACKSPACE': 0x08, 'DELETE': 0x2E, 'DEL': 0x2E, 'INSERT': 0x2D, 'INS': 0x2D,
    'HOME': 0x24, 'END': 0x23,
    'PAGEUP': 0x21, 'PGUP': 0x21, 'PAGEDOWN': 0x22, 'PGDN': 0x22,
    'LEFT': 0x25, 'RIGHT': 0x27, 'UP': 0x26, 'DOWN': 0x28,
    'MINUS': 0xBD, '-': 0xBD, 'EQUALS': 0xBB, '=': 0xBB,
    'LBRACKET': 0xDB, '[': 0xDB, 'RBRACKET': 0xDD, ']': 0xDD,
    'BACKSLASH': 0xDC, '\\': 0xDC,
    'SEMICOLON': 0xBA, ';': 0xBA, 'QUOTE': 0xDE, "'": 0xDE,
    'BACKTICK': 0xC0, '`': 0xC0,
    'COMMA': 0xBC, ',': 0xBC, 'PERIOD': 0xBE, '.': 0xBE, 'SLASH': 0xBF, '/': 0xBF,
  };
  return map[upper];
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SettingsService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: [
          // ===== 外观 =====
          _sectionHeader(context, '外观'),
          _themeTile(context, service),
          _customIconTile(context, service),
          _columnCountTile(context, service),
          _switchTile(
            context,
            icon: Icons.vertical_align_top,
            title: '窗口置顶',
            subtitle: '窗口始终显示在其他窗口之上',
            valueNotifier: service.alwaysOnTop,
            onChanged: (v) {
              service.setAlwaysOnTop(v);
              final hwnd = appWindow.handle;
              if (hwnd != null) {
                SetWindowPos(
                  hwnd,
                  v ? HWND_TOPMOST : HWND_NOTOPMOST,
                  0, 0, 0, 0,
                  SWP_NOMOVE | SWP_NOSIZE,
                );
              }
            },
          ),
          const Divider(height: 1),

          // ===== 行为 =====
          _sectionHeader(context, '行为'),
          _switchTile(
            context,
            icon: Icons.minimize,
            title: '关闭时最小化到托盘',
            subtitle: '点击关闭按钮时隐藏到系统托盘而不是退出',
            valueNotifier: service.minimizeToTray,
            onChanged: (v) => service.setMinimizeToTray(v),
          ),
          _switchTile(
            context,
            icon: Icons.launch,
            title: '启动时隐藏到托盘',
            subtitle: '程序启动后不显示窗口，只在托盘运行',
            valueNotifier: service.hideOnStartup,
            onChanged: (v) => service.setHideOnStartup(v),
          ),
          _switchTile(
            context,
            icon: Icons.power_settings_new,
            title: '开机自启',
            subtitle: 'Windows 启动时自动运行',
            valueNotifier: service.autoStart,
            onChanged: (v) => service.setAutoStart(v),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: service.autoStart,
            builder: (_, autoStart, _) => autoStart
                ? _startupDelayTile(context, service)
                : const SizedBox.shrink(),
          ),
          // 显示窗口快捷键
          _showWindowHotkeyTile(context, service),
          // 搜索快捷键
          _searchHotkeyTile(context, service),
          const Divider(height: 1),

          // ===== 列表管理 =====
          _sectionHeader(context, '列表管理'),
          _sortModeTile(context, service),
          _listTile(
            context,
            icon: Icons.file_download,
            title: '导出配置',
            subtitle: '将所有启动项导出为文件',
            onTap: () => _exportConfig(context),
          ),
          _listTile(
            context,
            icon: Icons.file_upload,
            title: '导入配置',
            subtitle: '从文件导入启动项',
            onTap: () => _importConfig(context),
          ),
          const Divider(height: 1),

          // ===== 当前运行的进程 =====
          _sectionHeader(context, '当前运行的进程'),
          _RunningProcessesSection(),
          const Divider(height: 1),

          // ===== 诊断 =====
          _sectionHeader(context, '诊断'),
          _listTile(
            context,
            icon: Icons.article_outlined,
            title: '启动日志',
            subtitle: '查看启动成功/失败记录',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LogsPage()),
              );
            },
          ),
          const Divider(height: 1),

          // ===== 关于 =====
          _sectionHeader(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            trailing: Text(
              UpdateService.currentVersion,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---------- 显示窗口快捷键 ----------

  Widget _showWindowHotkeyTile(BuildContext context, SettingsService service) {
    return ValueListenableBuilder<int?>(
      valueListenable: service.showWindowModifiers,
      builder: (_, mods, _) {
        final key = service.showWindowKey.value;
        final label = formatHotkeyLabel(mods, key);
        return ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('显示窗口快捷键'),
          subtitle: Text(
            label == '未设置' ? '未设置' : '按 $label 显示主窗口',
          ),
          trailing: TextButton(
            onPressed: () => _editShowWindowHotkey(context, service),
            child: Text(key == null ? '设置' : '修改'),
          ),
        );
      },
    );
  }

  void _editShowWindowHotkey(BuildContext context, SettingsService service) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('显示窗口快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入快捷键组合，例如：'),
            const SizedBox(height: 8),
            Text(
              '  Ctrl+Shift+Q\n  Ctrl+Alt+W\n  Win+Space',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '快捷键',
                hintText: 'Ctrl+Shift+Q',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              service.setShowWindowHotkey(null, null);
              HotkeyService().unregisterShowWindowHotkey();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除显示窗口快捷键')),
              );
            },
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
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

              // 注册新热键（先注销旧的）
              HotkeyService().unregisterShowWindowHotkey();
              HotkeyService().registerShowWindowHotkey(modifiers, vk);
              service.setShowWindowHotkey(modifiers, vk);

              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('显示窗口快捷键已设为 ${formatHotkeyLabel(modifiers, vk)}'),
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ---------- 搜索快捷键 ----------

  Widget _searchHotkeyTile(BuildContext context, SettingsService service) {
    return ValueListenableBuilder<int?>(
      valueListenable: service.searchHotkeyModifiers,
      builder: (_, mods, _) {
        final key = service.searchHotkeyKey.value;
        final label = formatHotkeyLabel(mods, key);
        return ListTile(
          leading: const Icon(Icons.search),
          title: const Text('全局搜索快捷键'),
          subtitle: Text(
            label == '未设置' ? '未设置' : '按 $label 打开全局搜索',
          ),
          trailing: TextButton(
            onPressed: () => _editSearchHotkey(context, service),
            child: Text(key == null ? '设置' : '修改'),
          ),
        );
      },
    );
  }

  void _editSearchHotkey(BuildContext context, SettingsService service) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全局搜索快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入快捷键组合，按下后在任何界面快速弹出搜索面板：'),
            const SizedBox(height: 8),
            Text(
              '  Ctrl+Shift+F\n  Alt+Space\n  Ctrl+Shift+Space',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '快捷键',
                hintText: 'Alt+Space',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              service.setSearchHotkey(null, null);
              HotkeyService().unregisterSearchHotkey();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除全局搜索快捷键')),
              );
            },
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
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

              // 注册新热键（先注销旧的）
              HotkeyService().unregisterSearchHotkey();
              HotkeyService().registerSearchHotkey(modifiers, vk);
              service.setSearchHotkey(modifiers, vk);

              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('全局搜索快捷键已设为 ${formatHotkeyLabel(modifiers, vk)}'),
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ---------- 其他 ----------

  Future<void> _exportConfig(BuildContext context) async {
    final path = await FilePicker.saveFile(
      dialogTitle: '导出配置',
      fileName: 'quick_launch_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    try {
      final json = ItemService().exportToJson();
      await File(path).writeAsString(json);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已导出')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _importConfig(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '导入配置',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final count =
          await ItemService().importFromFile(result.files.single.path!);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $count 个启动项')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _themeTile(BuildContext context, SettingsService service) {
    final icons = [Icons.light_mode, Icons.dark_mode, Icons.settings_brightness];
    final modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: service.themeMode,
      builder: (_, mode, _) => ListTile(
        leading: const Icon(Icons.palette),
        title: const Text('主题模式'),
        subtitle: Text(
            ['浅色', '深色', '跟随系统'][modes.indexOf(mode)]),
        trailing: SegmentedButton<ThemeMode>(
          segments: List.generate(3,
              (i) => ButtonSegment(value: modes[i], icon: Icon(icons[i], size: 18))),
          selected: {mode},
          onSelectionChanged: (s) => service.setThemeMode(s.first),
        ),
      ),
    );
  }

  Widget _customIconTile(BuildContext context, SettingsService service) {
    return ValueListenableBuilder<String?>(
      valueListenable: service.customIconPath,
      builder: (_, iconPath, _) => ListTile(
        leading: const Icon(Icons.image),
        title: const Text('自定义图标'),
        subtitle: Text(
          iconPath != null ? '已自定义' : '使用默认图标',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconPath != null)
              IconButton(
                icon: const Icon(Icons.restore),
                tooltip: '恢复默认',
                onPressed: () => _resetIcon(context, service),
              ),
            TextButton(
              onPressed: () => _pickIcon(context, service),
              child: Text(iconPath == null ? '选择' : '更换'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _columnCountTile(BuildContext context, SettingsService service) {
    return ValueListenableBuilder<int>(
      valueListenable: service.columnCount,
      builder: (_, count, _) => ListTile(
        leading: const Icon(Icons.grid_view),
        title: const Text('列表列数'),
        subtitle: Text(
          count <= 1 ? '单列' : '$count 列',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: count > 1
                  ? () => service.setColumnCount(count - 1)
                  : null,
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '列',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: count < 4
                  ? () => service.setColumnCount(count + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _pickIcon(BuildContext context, SettingsService service) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择图标文件',
      type: FileType.custom,
      allowedExtensions: ['ico'],
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;

    if (!context.mounted) return;

    // 先尝试设置窗口图标，成功了才保存路径
    const channel = MethodChannel('quick_launch/settings');
    try {
      final ok = await channel.invokeMethod<bool>('setAppIcon', path);
      if (ok != true) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图标文件无效，请选择其他 .ico 文件')),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置图标失败: $e')),
      );
      return;
    }

    // 窗口图标设置成功 → 保存路径并更新托盘图标
    service.setCustomIconPath(path);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图标已更新')),
    );
  }

  void _resetIcon(BuildContext context, SettingsService service) async {
    if (!context.mounted) return;

    // 先恢复默认窗口图标
    const channel = MethodChannel('quick_launch/settings');
    await channel.invokeMethod('setAppIcon', Platform.resolvedExecutable);

    // 清除已保存路径（触发监听器自动恢复托盘图标）
    service.setCustomIconPath(null);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复默认图标')),
    );
  }

  Widget _sortModeTile(BuildContext context, SettingsService service) {
    const labels = ['手动', '按名称', '按创建时间', '按类型', '最常用', '最近使用'];
    const modes = [
      SortMode.manual,
      SortMode.name,
      SortMode.created,
      SortMode.type,
      SortMode.mostUsed,
      SortMode.recentlyUsed,
    ];
    const icons = [
      Icons.touch_app,
      Icons.sort_by_alpha,
      Icons.access_time,
      Icons.category,
      Icons.trending_up,
      Icons.history,
    ];
    return ValueListenableBuilder<SortMode>(
      valueListenable: service.sortMode,
      builder: (_, mode, _) => ListTile(
        leading: const Icon(Icons.sort),
        title: const Text('排序方式'),
        trailing: DropdownButton<SortMode>(
          value: mode,
          underline: const SizedBox.shrink(),
          items: List.generate(6, (i) => DropdownMenuItem(
            value: modes[i],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icons[i], size: 18),
                const SizedBox(width: 8),
                Text(labels[i]),
              ],
            ),
          )),
          onChanged: (v) {
            if (v == null) return;
            service.setSortMode(v);
            ItemService().applySort();
          },
        ),
      ),
    );
  }

  Widget _startupDelayTile(BuildContext context, SettingsService service) {
    return ValueListenableBuilder<int>(
      valueListenable: service.startupDelay,
      builder: (_, delay, _) => ListTile(
        leading: const Icon(Icons.timer),
        title: const Text('开机自启延迟'),
        subtitle: Text(delay <= 0 ? '无延迟' : '延迟 $delay 秒'),
        trailing: SizedBox(
          width: 160,
          child: Slider(
            value: delay.toDouble(),
            min: 0,
            max: 60,
            divisions: 60,
            label: '${delay}s',
            onChanged: (v) => service.setStartupDelay(v.round()),
          ),
        ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required ValueNotifier<bool> valueNotifier,
    required void Function(bool) onChanged,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: valueNotifier,
      builder: (_, v, _) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Switch(value: v, onChanged: onChanged),
        onTap: () => onChanged(!v),
      ),
    );
  }

  Widget _listTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 当前运行的进程区块
class _RunningProcessesSection extends StatefulWidget {
  @override
  State<_RunningProcessesSection> createState() =>
      _RunningProcessesSectionState();
}

class _RunningProcessesSectionState extends State<_RunningProcessesSection> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<TrackedProcess>>(
      valueListenable: LaunchService().runningProcesses,
      builder: (_, processes, _) {
        if (processes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '没有正在运行的进程',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '共 ${processes.length} 个进程',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            ...processes.map((info) => _buildProcessTile(context, info)),
          ],
        );
      },
    );
  }

  Widget _buildProcessTile(BuildContext context, TrackedProcess info) {
    return ListTile(
      leading: const Icon(Icons.miscellaneous_services, color: Colors.blue),
      title: Text(info.itemName),
      subtitle: Text('PID: ${info.pid}  •  运行 ${info.runningDurationText}'),
      trailing: FilledButton.tonalIcon(
        onPressed: () {
          final messenger = ScaffoldMessenger.of(context);
          LaunchService().killProcess(info.itemId).then((ok) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(ok ? '已结束进程' : '结束进程失败'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          });
        },
        icon: const Icon(Icons.stop, size: 16),
        label: const Text('结束'),
        style: FilledButton.styleFrom(
          foregroundColor: Colors.red,
        ),
      ),
    );
  }
}
