// GitHub Issues 页面 - 完整 CRUD UI
// 位于 core 模块，lab/demos 只做导入

import 'package:flutter/material.dart';
import 'github_issues_models.dart';
import 'github_issues_service.dart';

class GithubIssuesPage extends StatefulWidget {
  final String owner;
  final String repo;
  final String token;

  const GithubIssuesPage({
    super.key,
    required this.owner,
    required this.repo,
    required this.token,
  });

  @override
  State<GithubIssuesPage> createState() => _GithubIssuesPageState();
}

class _GithubIssuesPageState extends State<GithubIssuesPage>
    with SingleTickerProviderStateMixin {
  late GithubIssuesService _service;
  late TabController _tabController;

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _labelController = TextEditingController();

  List<IssueModel> _issues = [];
  bool _loading = false;
  String _error = '';
  String _stateFilter = 'open'; // 'all' | 'open' | 'closed'

  @override
  void initState() {
    super.initState();
    _service = GithubIssuesService(
      owner: widget.owner,
      repo: widget.repo,
      token: widget.token,
    );
    _tabController = TabController(length: 2, vsync: this);
    _fetchIssues();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  // ============================================================
  // CRUD 操作
  // ============================================================

  Future<void> _fetchIssues() async {
    setState(() => _loading = true);
    try {
      final list = await _service.listIssues(state: _stateFilter);
      setState(() {
        _issues = list;
        _loading = false;
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
      await _service.createIssue(CreateIssueRequest(
        title: title,
        body: _bodyController.text.trim(),
      ));
      _titleController.clear();
      _bodyController.clear();
      _showMsg('创建成功');
      _tabController.animateTo(0);
      _fetchIssues();
    } on GithubApiException catch (e) {
      _showMsg('创建失败: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _closeIssue(IssueModel issue) async {
    setState(() => _loading = true);
    try {
      await _service.closeIssue(issue.number);
      _showMsg('已关闭 #${issue.number}');
      _fetchIssues();
    } on GithubApiException catch (e) {
      _showMsg('关闭失败: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _reopenIssue(IssueModel issue) async {
    setState(() => _loading = true);
    try {
      await _service.reopenIssue(issue.number);
      _showMsg('已重新打开 #${issue.number}');
      _fetchIssues();
    } on GithubApiException catch (e) {
      _showMsg('操作失败: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ============================================================
  // UI 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.owner}/${widget.repo} Issues'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Badge(
                label: Text('${_issues.length}'),
                isLabelVisible: _issues.isNotEmpty,
                child: const Icon(Icons.list),
              ),
              text: _stateFilter == 'all' ? '全部' : _stateFilter == 'open' ? '打开' : '已关闭',
            ),
            const Tab(icon: Icon(Icons.add), text: '创建'),
          ],
        ),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchIssues,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildListTab(), _buildCreateTab()],
      ),
    );
  }

  Widget _buildListTab() {
    if (_loading && _issues.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty && _issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchIssues,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 状态筛选器
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('全部')),
                    ButtonSegment(value: 'open', label: Text('打开')),
                    ButtonSegment(value: 'closed', label: Text('已关闭')),
                  ],
                  selected: {_stateFilter},
                  onSelectionChanged: (s) {
                    setState(() => _stateFilter = s.first);
                    _fetchIssues();
                  },
                ),
              ),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: _issues.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bug_report_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _stateFilter == 'all'
                            ? '暂无 Issues'
                            : _stateFilter == 'open'
                                ? '暂无 Open Issues'
                                : '暂无已关闭的 Issues',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
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
              hintText: '简短描述问题或功能',
            ),
            maxLength: 256,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            decoration: const InputDecoration(
              labelText: '内容（可选）',
              border: OutlineInputBorder(),
              hintText: '详细描述...',
              alignLabelWithHint: true,
            ),
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '标签（可选，多个用逗号分隔）',
              border: OutlineInputBorder(),
              hintText: 'bug, enhancement',
            ),
          ),
          const SizedBox(height: 24),
          if (_error.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
            const SizedBox(height: 16),
          ],
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
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(IssueModel issue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _IssueDetailSheet(
        issue: issue,
        service: _service,
        onClose: () {
          Navigator.pop(ctx);
          _fetchIssues();
        },
        onReopen: () {
          Navigator.pop(ctx);
          _fetchIssues();
        },
      ),
    );
  }
}

// ============================================================
// Issue 卡片
// ============================================================

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
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'close') onClose();
                  if (v == 'reopen') onReopen();
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

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ============================================================
// Issue 详情 Sheet
// ============================================================

class _IssueDetailSheet extends StatefulWidget {
  final IssueModel issue;
  final GithubIssuesService service;
  final VoidCallback onClose;
  final VoidCallback onReopen;

  const _IssueDetailSheet({
    required this.issue,
    required this.service,
    required this.onClose,
    required this.onReopen,
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
      if (_issue.state == 'open') {
        await widget.service.closeIssue(_issue.number);
        widget.onClose();
        _showMsg('已关闭 #${_issue.number}');
      } else {
        await widget.service.reopenIssue(_issue.number);
        widget.onReopen();
        _showMsg('已重新打开 #${_issue.number}');
      }
    } on GithubApiException catch (e) {
      _showMsg(e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _issue.state == 'open';
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
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
            // Meta
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    isOpen ? Icons.error_outline : Icons.check_circle,
                    size: 16,
                    color: isOpen ? Colors.green : Colors.purple,
                  ),
                  label: Text(isOpen ? 'Open' : 'Closed'),
                ),
                Chip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(_issue.author),
                ),
                Chip(
                  avatar: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_fmtDate(_issue.createdAt)),
                ),
              ],
            ),
            const Divider(height: 24),
            // Body
            SelectableText(
              _issue.body ?? '（无内容）',
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 24),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _launchUrl(_issue.url),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('在 GitHub 打开'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _toggleState,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOpen ? Colors.orange : Colors.green,
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isOpen ? Icons.close : Icons.refresh),
                    label: Text(isOpen ? '关闭 Issue' : '重新打开'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loading ? null : () => _showCloneDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                  ),
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

  void _showCloneDialog() {
    final titleController = TextEditingController(text: _issue.title);
    final bodyController = TextEditingController(text: _issue.body ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('标题不能为空')),
                );
                return;
              }
              Navigator.pop(ctx);
              await _cloneIssue(title, bodyController.text.trim());
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _cloneIssue(String title, String body) async {
    setState(() => _loading = true);
    try {
      final newIssue = await widget.service.createIssue(
        CreateIssueRequest(title: title, body: body),
      );
      if (mounted) {
        _showMsg('已克隆为 #${newIssue.number}');
        Navigator.pop(context); // 关闭详情 sheet
      }
    } on GithubApiException catch (e) {
      _showMsg(e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _launchUrl(String url) {
    // 在真实环境中使用 url_launcher
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('URL: $url')),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
