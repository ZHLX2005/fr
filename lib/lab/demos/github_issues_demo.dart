import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../lab_container.dart';

/// GitHub Issues Demo
class GithubIssuesDemo extends DemoPage {
  @override
  String get title => 'GitHub Issues';

  @override
  String get description => '查询 ZHLX2005/fr 项目的 Issues，支持创建新 Issue';

  @override
  Widget buildPage(BuildContext context) {
    return const GithubIssuesPage();
  }
}

class GithubIssuesPage extends StatefulWidget {
  const GithubIssuesPage({super.key});

  @override
  State<GithubIssuesPage> createState() => _GithubIssuesPageState();
}

class _GithubIssuesPageState extends State<GithubIssuesPage>
    with SingleTickerProviderStateMixin {
  static const String _owner = 'ZHLX2005';
  static const String _repo = 'fr';
  static const String _apiBase = 'https://api.github.com/repos/$_owner/$_repo/issues';

  late TabController _tabController;
  final _tokenController = TextEditingController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  List<Map<String, dynamic>> _issues = [];
  bool _loading = false;
  bool _tokenSet = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tokenController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Map<String, String> get _headers {
    final h = <String, String>{
      'Accept': 'application/vnd.github+json',
    };
    if (_tokenController.text.isNotEmpty) {
      h['Authorization'] = 'Bearer ${_tokenController.text}';
    }
    return h;
  }

  Future<void> _fetchIssues() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final resp = await http.get(
        Uri.parse('$_apiBase?state=open&per_page=50'),
        headers: _headers,
      );

      if (resp.statusCode == 200) {
        final list = json.decode(resp.body) as List;
        setState(() {
          _issues = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'HTTP ${resp.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createIssue() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      _showMsg('标题不能为空');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final resp = await http.post(
        Uri.parse(_apiBase),
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'title': title,
          'body': body.isEmpty ? null : body,
        }),
      );

      if (resp.statusCode == 201) {
        _titleController.clear();
        _bodyController.clear();
        _showMsg('Issue 创建成功');
        _fetchIssues();
        _tabController.animateTo(0);
      } else {
        setState(() {
          _error = 'HTTP ${resp.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: '列表'),
            Tab(icon: Icon(Icons.add), text: '创建'),
          ],
        ),
        title: const Text('GitHub Issues'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildListTab(), _buildCreateTab()],
      ),
    );
  }

  Widget _buildListTab() {
    return Column(
      children: [
        // Token 设置区
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '输入 GitHub PAT',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              if (!_tokenSet && _tokenController.text.isNotEmpty)
                ElevatedButton(
                  onPressed: () => setState(() => _tokenSet = true),
                  child: const Text('确认'),
                )
              else if (_tokenSet)
                OutlinedButton(
                  onPressed: () => setState(() {
                    _tokenSet = false;
                    _tokenController.clear();
                  }),
                  child: const Text('清除'),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _loading ? null : _fetchIssues,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        // Issues 列表
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _issues.isEmpty
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
                            _error.isNotEmpty ? _error : '暂无 Open 的 Issues',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_error.isEmpty)
                            const Text('点击"刷新"加载 Issues'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _issues.length,
                      itemBuilder: (context, index) {
                        final issue = _issues[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getColor(
                                issue['state']?.toString() ?? 'open',
                              ),
                              child: Text(
                                '#${issue['number']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: Text(
                              issue['title'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              issue['user']?['login'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showIssueDetail(issue),
                          ),
                        );
                      },
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
              labelText: 'Issue 标题 *',
              border: OutlineInputBorder(),
              hintText: '简短描述问题或功能',
            ),
            maxLength: 256,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyController,
            decoration: const InputDecoration(
              labelText: 'Issue 内容（可选）',
              border: OutlineInputBorder(),
              hintText: '详细描述...',
              alignLabelWithHint: true,
            ),
            maxLines: 8,
          ),
          const SizedBox(height: 16),
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                _error,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          SizedBox(
            child: ElevatedButton.icon(
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
          ),
        ],
      ),
    );
  }

  Color _getColor(String state) {
    return state == 'open' ? Colors.green : Colors.purple;
  }

  void _showIssueDetail(Map<String, dynamic> issue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getColor(issue['state']?.toString() ?? 'open'),
                    child: Text(
                      '#${issue['number']}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      issue['title'] ?? '',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'by ${issue['user']?['login'] ?? 'unknown'} · ${issue['created_at']?.toString().substring(0, 10) ?? ''}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 12,
                ),
              ),
              const Divider(height: 24),
              SelectableText(
                issue['body'] ?? '（无内容）',
                style: const TextStyle(height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void registerGithubIssuesDemo() {
  demoRegistry.register(GithubIssuesDemo());
}
