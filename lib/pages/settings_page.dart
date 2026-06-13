import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:win32/win32.dart';
import '../services/settings_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SettingsService();
    final theme = Theme.of(context);

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
          // ---- 外观 ----
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

          // ---- 行为 ----
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
            icon: Icons.power_settings_new,
            title: '开机自启',
            subtitle: 'Windows 启动时自动运行',
            valueNotifier: service.autoStart,
            onChanged: (v) => service.setAutoStart(v),
          ),
          const Divider(height: 1),

          // ---- 关于 ----
          _sectionHeader(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            trailing: Text(
              '1.0.0',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
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
    final labels = ['浅色', '深色', '跟随系统'];
    final modes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];
    final icons = [Icons.light_mode, Icons.dark_mode, Icons.settings_brightness];

    return ListTile(
      leading: const Icon(Icons.palette),
      title: const Text('主题模式'),
      subtitle: Text(labels[modes.indexOf(service.themeMode.value)]),
      trailing: SegmentedButton<ThemeMode>(
        segments: List.generate(3, (i) =>
          ButtonSegment(value: modes[i], icon: Icon(icons[i], size: 18)),
        ),
        selected: {service.themeMode.value},
        onSelectionChanged: (set) => service.setThemeMode(set.first),
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
      builder: (_, value, _) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
        onTap: () => onChanged(!value),
      ),
    );
  }
}
