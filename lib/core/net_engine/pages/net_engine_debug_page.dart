import 'package:flutter/material.dart';

import '../services/debug_log_service.dart';

class NetEngineDebugPage extends StatelessWidget {
  const NetEngineDebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('调试日志'),
          actions: [
            IconButton(
              icon: Icon(Icons.delete_outline),
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
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case LogLevel.info:
        return Theme.of(context).colorScheme.primary;
      case LogLevel.warning:
        return Theme.of(context).colorScheme.tertiary;
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
          Text(entry.levelIcon, style: TextStyle(fontSize: 12)),
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hub_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(height: 16),
                Text('暂无状态转换记录'),
                SizedBox(height: 8),
                Text('状态转换会显示在这里', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

  Color _getServiceColor(BuildContext context, String service) {
    switch (service) {
      case 'Localnet':
        return Theme.of(context).colorScheme.primary;
      case 'Discovery':
        return Theme.of(context).colorScheme.primary;
      case 'Message':
        return Theme.of(context).colorScheme.tertiary;
      case 'Config':
        return Theme.of(context).colorScheme.tertiary;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceColor = _getServiceColor(context, entry.service);

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
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    _StateBadge(state: entry.toState, isActive: true),
                  ],
                ),
                if (entry.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.note!,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  Color _getStateColor(BuildContext context, String state) {
    switch (state) {
      case 'INIT':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case 'LOADING':
        return Theme.of(context).colorScheme.tertiary;
      case 'READY':
        return Theme.of(context).colorScheme.primary;
      case 'IDLE':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case 'STARTING':
        return Theme.of(context).colorScheme.primary;
      case 'RUNNING':
        return Theme.of(context).colorScheme.primary;
      case 'STOPPING':
        return Theme.of(context).colorScheme.tertiary;
      case 'ERROR':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStateColor(context, state);
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
