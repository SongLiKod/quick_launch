import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:win32/win32.dart';
import '../services/settings_service.dart';
import '../services/item_service.dart';
import 'logs_page.dart';

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
          if (service.autoStart.value) _startupDelayTile(context, service),
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
              '1.0.0',
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
      final count = await ItemService().importFromFile(result.files.single.path!);
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

  // ---------- 组件 ----------

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

    return ListTile(
      leading: const Icon(Icons.palette),
      title: const Text('主题模式'),
      subtitle: Text(['浅色', '深色', '跟随系统'][modes.indexOf(service.themeMode.value)]),
      trailing: SegmentedButton<ThemeMode>(
        segments: List.generate(3, (i) =>
          ButtonSegment(value: modes[i], icon: Icon(icons[i], size: 18)),
        ),
        selected: {service.themeMode.value},
        onSelectionChanged: (s) => service.setThemeMode(s.first),
      ),
    );
  }

  Widget _sortModeTile(BuildContext context, SettingsService service) {
    const labels = ['手动', '按名称', '按创建时间'];
    const modes = [SortMode.manual, SortMode.name, SortMode.created];

    return ListTile(
      leading: const Icon(Icons.sort),
      title: const Text('排序方式'),
      subtitle: Text(labels[modes.indexOf(service.sortMode.value)]),
      trailing: SegmentedButton<SortMode>(
        segments: List.generate(3, (i) =>
          ButtonSegment(
            value: modes[i],
            label: Text(labels[i], style: const TextStyle(fontSize: 12)),
          ),
        ),
        selected: {service.sortMode.value},
        onSelectionChanged: (s) {
          service.setSortMode(s.first);
          ItemService().applySort();
        },
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
