import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// 主界面底部新版本提示横幅：点击可直接在界面内下载并安装
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<UpdateState>(
      valueListenable: UpdateService().state,
      builder: (context, s, _) {
        switch (s.phase) {
          case UpdatePhase.available:
            return _banner(
              theme,
              color: theme.colorScheme.primaryContainer,
              icon: Icons.system_update_alt,
              text:
                  '发现新版本 v${s.latestVersion}（当前 v${UpdateService.currentVersion}）',
              actionLabel: '安装',
              onTap: UpdateService().downloadAndInstall,
            );
          case UpdatePhase.downloading:
            final percent = s.progress >= 0
                ? '${(s.progress * 100).toStringAsFixed(0)}%'
                : '';
            return _banner(
              theme,
              color: theme.colorScheme.surfaceContainerHighest,
              icon: Icons.downloading,
              text: '正在下载新版本 v${s.latestVersion} $percent',
              progress: s.progress >= 0 ? s.progress : null,
            );
          case UpdatePhase.installing:
            return _banner(
              theme,
              color: theme.colorScheme.secondaryContainer,
              icon: Icons.settings_suggest,
              text: '下载完成，正在安装新版本，完成后应用将自动重启',
            );
          case UpdatePhase.installFailed:
            return _banner(
              theme,
              color: theme.colorScheme.errorContainer,
              icon: Icons.error_outline,
              text: '新版本安装失败: ${s.error ?? '未知错误'}',
              actionLabel: '重试',
              onTap: UpdateService().downloadAndInstall,
            );
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _banner(
    ThemeData theme, {
    required Color color,
    required IconData icon,
    required String text,
    double? progress,
    String? actionLabel,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(width: 10),
                    FilledButton.tonal(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ],
              ),
            ),
            if (progress != null)
              LinearProgressIndicator(value: progress, minHeight: 2),
          ],
        ),
      ),
    );
  }
}
