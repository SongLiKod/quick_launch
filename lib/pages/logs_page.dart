import 'package:flutter/material.dart';
import '../services/launch_log_service.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logService = LaunchLogService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('启动日志'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清空日志'),
                  content: const Text('确定要清空所有启动日志吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('清空', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await logService.clearLogs();
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<LaunchLogEntry>>(
        valueListenable: logService.logs,
        builder: (_, logs, _) {
          if (logs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无启动日志', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final log = logs[i];
              final timeStr = '${log.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${log.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${log.timestamp.second.toString().padLeft(2, '0')}';
              final dateStr = '${log.timestamp.month}/${log.timestamp.day}';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: ListTile(
                  leading: Icon(
                    log.success ? Icons.check_circle : Icons.error,
                    color: log.success ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    log.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.message, style: const TextStyle(fontSize: 12)),
                      Text(
                        '$dateStr $timeStr  |  ${log.targetPath}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
