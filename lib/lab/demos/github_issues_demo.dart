// GitHub Issues LabDemo
// lab 层只做 token 状态管理 + 页面组装，CRUD 逻辑在 core

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/github/github.dart';
import '../lab_container.dart';

class GithubIssuesDemo extends DemoPage {
  @override
  String get title => 'GitHub Issues';

  @override
  String get description => 'CRUD · 列表 / 创建 / 关闭 / 重新打开';

  @override
  Widget buildPage(BuildContext context) {
    return const _GithubIssuesDemoShell();
  }
}

class _GithubIssuesDemoShell extends StatefulWidget {
  const _GithubIssuesDemoShell();

  @override
  State<_GithubIssuesDemoShell> createState() => _GithubIssuesDemoShellState();
}

class _GithubIssuesDemoShellState extends State<_GithubIssuesDemoShell> {
  static const String _owner = 'ZHLX2005';
  static const String _repo = 'is';
  static const String _actionsRepo = 'fr';
  static const String _tokenKey = 'github_pat_token';

  final _tokenController = TextEditingController();
  bool _tokenConfirmed = false;
  String _inputToken = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  Future<void> _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved != null && saved.isNotEmpty) {
      _inputToken = saved;
      _tokenController.text = saved;
      setState(() => _tokenConfirmed = true);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token.isNotEmpty) {
      await prefs.setString(_tokenKey, token);
    } else {
      await prefs.remove(_tokenKey);
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_tokenConfirmed) {
      return _buildTokenInput();
    }
    return GithubPage(
      issuesOwner: _owner,
      issuesRepo: _repo,
      actionsOwner: _owner,
      actionsRepo: _actionsRepo,
      token: _inputToken,
    );
  }

  Widget _buildTokenInput() {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.key,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'GitHub PAT Token',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '访问 $_owner/$_repo 的 Issues 需要认证',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Personal Access Token',
                  border: OutlineInputBorder(),
                  hintText: 'ghp_xxxxxxxxxxxx',
                ),
                obscureText: true,
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirm,
                  child: const Text('确认并进入'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _inputToken = _tokenController.text.trim();
                  if (_inputToken.isNotEmpty) {
                    _saveToken(_inputToken);
                  }
                  setState(() => _tokenConfirmed = true);
                },
                child: const Text('使用空 Token（只读 public）'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 PAT Token')));
      return;
    }
    _inputToken = token;
    _saveToken(token);
    setState(() => _tokenConfirmed = true);
  }
}

void registerGithubIssuesDemo() {
  demoRegistry.register(GithubIssuesDemo());
}
