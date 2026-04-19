import 'package:flutter/material.dart';

import 'github_actions_models.dart';
import 'github_actions_service.dart';
import 'github_api_exception.dart';

class GithubActionsTab extends StatefulWidget {
  final GithubActionsService service;
  final String repoLabel;

  const GithubActionsTab({
    super.key,
    required this.service,
    required this.repoLabel,
  });

  @override
  State<GithubActionsTab> createState() => _GithubActionsTabState();
}

class _GithubActionsTabState extends State<GithubActionsTab> {
  List<WorkflowRunModel> _runs = [];
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchRuns();
  }

  Future<void> _fetchRuns() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final runs = await widget.service.listLatestWorkflowRunsWithJobs(
        perPage: 3,
      );
      setState(() {
        _runs = runs;
      });
    } on GithubApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty && _runs.isEmpty) {
      return _GithubActionsErrorState(message: _error, onRetry: _fetchRuns);
    }

    if (_runs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchRuns,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            _GithubActionsEmptyState(
              icon: Icons.account_tree_outlined,
              title: '没有 workflow runs',
              subtitle: '仓库: ${widget.repoLabel}',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchRuns,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '仅显示最新 3 个 runs，用于快速判断是否完成',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _fetchRuns,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._runs.map((run) => _WorkflowRunCard(run: run)),
        ],
      ),
    );
  }
}

class _WorkflowRunCard extends StatelessWidget {
  final WorkflowRunModel run;

  const _WorkflowRunCard({required this.run});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(run.status, run.conclusion);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(_statusIcon(run.status, run.conclusion), color: color),
        ),
        title: Text(
          run.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Run #${run.id} · ${run.branch} · ${run.event}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _statusText(run.status, run.conclusion),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              run.isCompleted ? (run.isSuccess ? '已完成' : '未通过') : '进行中',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
          ],
        ),
        children: [
          _GithubActionsMetaRow(
            label: 'Updated',
            value: run.updatedAt == null ? '-' : _fmtDateTime(run.updatedAt!),
          ),
          const SizedBox(height: 8),
          _GithubActionsMetaRow(
            label: 'URL',
            value: run.url.isEmpty ? '-' : run.url,
          ),
          const SizedBox(height: 12),
          if (run.jobs.isEmpty)
            const Text('没有 jobs')
          else
            ...run.jobs.map(
              (job) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WorkflowJobTile(job: job),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkflowJobTile extends StatelessWidget {
  final WorkflowJobModel job;

  const _WorkflowJobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(job.status, job.conclusion);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(job.status, job.conclusion), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'status=${job.status}, conclusion=${job.conclusion ?? '-'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12,
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

class _GithubActionsMetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _GithubActionsMetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}

class _GithubActionsErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GithubActionsErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _GithubActionsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _GithubActionsEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(title),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

Color _statusColor(String status, String? conclusion) {
  if (status != 'completed') {
    return Colors.orange;
  }
  switch (conclusion) {
    case 'success':
      return Colors.green;
    case 'failure':
    case 'timed_out':
    case 'cancelled':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

IconData _statusIcon(String status, String? conclusion) {
  if (status != 'completed') {
    return Icons.hourglass_top_rounded;
  }
  switch (conclusion) {
    case 'success':
      return Icons.check_circle_rounded;
    case 'failure':
    case 'timed_out':
      return Icons.error_rounded;
    case 'cancelled':
      return Icons.cancel_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

String _statusText(String status, String? conclusion) {
  if (status != 'completed') {
    return 'IN PROGRESS';
  }
  return (conclusion ?? 'completed').toUpperCase();
}

String _fmtDateTime(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
