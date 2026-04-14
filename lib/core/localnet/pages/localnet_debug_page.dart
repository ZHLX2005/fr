import 'package:flutter/material.dart';

import '../services/debug_log_service.dart';

class LocalnetDebugPage extends StatelessWidget {
  const LocalnetDebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('调试日志'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                debugLog.clear();
              },
              tooltip: '清除日志',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '日志', icon: Icon(Icons.list)),
              Tab(text: '状态机', icon: Icon(Icons.hub)),
            ],
          ),
        ),
        body: const TabBarView(children: [_LogTab(), _StateMachineTab()]),
      ),
    );
  }
}

class _LogTab extends StatelessWidget {
  const _LogTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LogEntry>>(
      stream: debugLog.logsStream,
      initialData: debugLog.logs,
      builder: (context, snapshot) {
        final logs = snapshot.data ?? [];

        if (logs.isEmpty) {
          return const Center(child: Text('暂无日志'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return _LogEntryTile(entry: log);
          },
        );
      },
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;

  const _LogEntryTile({required this.entry});

  Color _getLevelColor(BuildContext context) {
    switch (entry.level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Theme.of(context).colorScheme.primary;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Theme.of(context).colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLevelColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.formattedTime,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Text(entry.levelIcon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.tag,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.message,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateMachineTab extends StatelessWidget {
  const _StateMachineTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StateMachineEntry>>(
      stream: debugLog.stateMachineStream,
      initialData: debugLog.stateMachineLogs,
      builder: (context, snapshot) {
        final logs = snapshot.data ?? [];

        if (logs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('暂无状态转换记录'),
                SizedBox(height: 8),
                Text('状态转换会显示在这里', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final entry = logs[index];
            return _StateMachineTile(entry: entry);
          },
        );
      },
    );
  }
}

class _StateMachineTile extends StatelessWidget {
  final StateMachineEntry entry;

  const _StateMachineTile({required this.entry});

  Color _getServiceColor(String service) {
    switch (service) {
      case 'Localnet':
        return Colors.blue;
      case 'Discovery':
        return Colors.green;
      case 'Message':
        return Colors.purple;
      case 'Config':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceColor = _getServiceColor(entry.service);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // 时间
          Text(
            entry.formattedTime,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          // 服务标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: serviceColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.service,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: serviceColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 状态转换
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StateBadge(state: entry.fromState, isActive: false),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                    _StateBadge(state: entry.toState, isActive: true),
                  ],
                ),
                if (entry.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.note!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final String state;
  final bool isActive;

  const _StateBadge({required this.state, required this.isActive});

  Color _getStateColor(String state) {
    switch (state) {
      case 'INIT':
        return Colors.grey;
      case 'LOADING':
        return Colors.orange;
      case 'READY':
        return Colors.green;
      case 'IDLE':
        return Colors.grey;
      case 'STARTING':
        return Colors.blue;
      case 'RUNNING':
        return Colors.green;
      case 'STOPPING':
        return Colors.orange;
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActive ? 0.3 : 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        state,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
