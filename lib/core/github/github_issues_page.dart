import 'package:flutter/material.dart';

import 'github_api_exception.dart';
import 'github_issues_models.dart';
import 'github_issues_service.dart';

class GithubIssuesTab extends StatefulWidget {
  final GithubIssuesService service;

  const GithubIssuesTab({super.key, required this.service});

  @override
  State<GithubIssuesTab> createState() => _GithubIssuesTabState();
}

class _GithubIssuesTabState extends State<GithubIssuesTab> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _labelController = TextEditingController();

  List<IssueModel> _issues = [];
  bool _loading = false;
  String _error = '';
  String _stateFilter = 'open';

  @override
  void initState() {
    super.initState();
    _fetchIssues();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _fetchIssues() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await widget.service.listIssues(state: _stateFilter);
      setState(() {
        _issues = list;
      });
    } on GithubApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createIssue() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMsg('标题不能为空');
      return;
    }

    setState(() => _loading = true);
    try {
      final labels = _labelController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await widget.service.createIssue(
        CreateIssueRequest(
          title: title,
          body: _bodyController.text.trim(),
          labels: labels.isEmpty ? null : labels,
        ),
      );
      _titleController.clear();
      _bodyController.clear();
      _labelController.clear();
      _showMsg('Issue 创建成功');
      await _fetchIssues();
    } on GithubApiException catch (e) {
      _showMsg('创建失败: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _closeIssue(IssueModel issue) async {
    setState(() => _loading = true);
    try {
      await widget.service.closeIssue(issue.number);
      _showMsg('已关闭 #${issue.number}');
      await _fetchIssues();
    } on GithubApiException catch (e) {
      _showMsg('关闭失败: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _reopenIssue(IssueModel issue) async {
    setState(() => _loading = true);
    try {
      await widget.service.reopenIssue(issue.number);
      _showMsg('已重新打开 #${issue.number}');
      await _fetchIssues();
    } on GithubApiException catch (e) {
      _showMsg('操作失败: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showDetail(IssueModel issue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _IssueDetailSheet(
        issue: issue,
        service: widget.service,
        onUpdated: _fetchIssues,
      ),
    );
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(text: 'Issues'),
                Tab(text: 'Create'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [_buildListTab(), _buildCreateTab()]),
          ),
        ],
      ),
    );
  }

  Widget _buildListTab() {
    if (_loading && _issues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty && _issues.isEmpty) {
      return _GithubIssuesErrorState(message: _error, onRetry: _fetchIssues);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('全部')),
                    ButtonSegment(value: 'open', label: Text('打开')),
                    ButtonSegment(value: 'closed', label: Text('关闭')),
                  ],
                  selected: {_stateFilter},
                  onSelectionChanged: (selection) {
                    setState(() => _stateFilter = selection.first);
                    _fetchIssues();
                  },
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _fetchIssues,
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
        ),
        Expanded(
          child: _issues.isEmpty
              ? const _GithubIssuesEmptyState(
                  icon: Icons.inbox_outlined,
                  title: '没有可显示的 Issues',
                )
              : RefreshIndicator(
                  onRefresh: _fetchIssues,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _issues.length,
                    itemBuilder: (context, index) {
                      final issue = _issues[index];
                      return _IssueCard(
                        issue: issue,
                        onTap: () => _showDetail(issue),
                        onClose: () => _closeIssue(issue),
                        onReopen: () => _reopenIssue(issue),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '标题 *',
              border: OutlineInputBorder(),
            ),
            maxLength: 256,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            decoration: const InputDecoration(
              labelText: '内容',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '标签，多个用逗号分隔',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loading ? null : _createIssue,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('创建 Issue'),
          ),
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final IssueModel issue;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onReopen;

  const _IssueCard({
    required this.issue,
    required this.onTap,
    required this.onClose,
    required this.onReopen,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = issue.state == 'open';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isOpen ? Colors.green : Colors.purple,
                radius: 16,
                child: Text(
                  '#${issue.number}',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'by ${issue.author} · ${_fmtDate(issue.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'close') {
                    onClose();
                  } else if (value == 'reopen') {
                    onReopen();
                  }
                },
                itemBuilder: (_) => [
                  if (isOpen)
                    const PopupMenuItem(value: 'close', child: Text('关闭 Issue'))
                  else
                    const PopupMenuItem(value: 'reopen', child: Text('重新打开')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueDetailSheet extends StatefulWidget {
  final IssueModel issue;
  final GithubIssuesService service;
  final Future<void> Function() onUpdated;

  const _IssueDetailSheet({
    required this.issue,
    required this.service,
    required this.onUpdated,
  });

  @override
  State<_IssueDetailSheet> createState() => _IssueDetailSheetState();
}

class _IssueDetailSheetState extends State<_IssueDetailSheet> {
  late IssueModel _issue;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _issue = widget.issue;
  }

  Future<void> _toggleState() async {
    setState(() => _loading = true);
    try {
      final updated = _issue.state == 'open'
          ? await widget.service.closeIssue(_issue.number)
          : await widget.service.reopenIssue(_issue.number);
      setState(() => _issue = updated);
      await widget.onUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated.state == 'open'
                  ? '已重新打开 #${updated.number}'
                  : '已关闭 #${updated.number}',
            ),
          ),
        );
      }
    } on GithubApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _cloneIssue(String title, String body) async {
    setState(() => _loading = true);
    try {
      final created = await widget.service.createIssue(
        CreateIssueRequest(title: title, body: body),
      );
      await widget.onUpdated();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已克隆为 #${created.number}')));
        Navigator.pop(context);
      }
    } on GithubApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showCloneDialog() {
    final titleController = TextEditingController(text: _issue.title);
    final bodyController = TextEditingController(text: _issue.body ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('克隆 Issue'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(const SnackBar(content: Text('标题不能为空')));
                return;
              }
              Navigator.pop(dialogContext);
              _cloneIssue(title, bodyController.text.trim());
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _issue.state == 'open';

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isOpen ? Colors.green : Colors.purple,
                  child: Text(
                    '#${_issue.number}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _issue.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(isOpen ? 'Open' : 'Closed')),
                Chip(label: Text(_issue.author)),
                Chip(label: Text(_fmtDate(_issue.createdAt))),
              ],
            ),
            const Divider(height: 24),
            SelectableText(
              (_issue.body == null || _issue.body!.trim().isEmpty)
                  ? '（无内容）'
                  : _issue.body!,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('GitHub URL: ${_issue.url}'),
                              ),
                            );
                          },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('查看 URL'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _toggleState,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isOpen ? Icons.close : Icons.refresh),
                    label: Text(isOpen ? '关闭' : '重新打开'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _showCloneDialog,
                  icon: const Icon(Icons.copy),
                  label: const Text('克隆'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GithubIssuesErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GithubIssuesErrorState({required this.message, required this.onRetry});

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

class _GithubIssuesEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  const _GithubIssuesEmptyState({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(title),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
