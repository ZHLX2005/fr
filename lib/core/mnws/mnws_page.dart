import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/global/button/main.dart';
import '../ui/global/nav/main.dart';
import 'mnws_config.dart';
import 'mnws_models.dart';
import 'mnws_providers.dart';
import 'mnws_service.dart';
import 'nxkv_models.dart';

/// mn-ws 的 lab demo 页面。
///
/// 三块：
///   ① **连接** —— 统一登录态 → mn-ws 业务令牌 → 拉目录（服务端支持哪些端口、应用名是什么）
///   ② **仓库** —— 经桥访问 nx-kv 的仓库管理（当前只实现这一块）
///   ③ **请求** —— 内置请求台：任意方法/路径/头/体，发出去看响应
///
/// ── 为什么要「先登录再看应用」 ────────────────────────────────────────────
/// 目录接口 `/api/catalog` 要凭据（`X-Mn-Ws-Token`），而且按用户过滤 ——
/// 具名用户只看得到自己名下的桥。所以「有哪些应用」这个问题本身就依赖登录态，
/// 不是「先列出来再决定要不要登录」。
class MnWsPage extends ConsumerStatefulWidget {
  const MnWsPage({super.key});

  @override
  ConsumerState<MnWsPage> createState() => _MnWsPageState();
}

class _MnWsPageState extends ConsumerState<MnWsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  // ── 连接 ──
  MnWsReadiness? _readiness;
  List<MnWsApp> _apps = const [];
  bool _loading = true;
  bool _authorizing = false;
  String? _error;

  // ── 仓库（nx-kv）──
  static const String _repoApp = 'nx-kv';
  List<NxKvRepo> _repos = const [];
  bool _reposLoading = false;
  String? _repoError;

  // ── 请求台 ──
  final TextEditingController _methodCtrl = TextEditingController(text: 'GET');
  final TextEditingController _pathCtrl = TextEditingController(text: '/api/repos');
  final TextEditingController _bodyCtrl = TextEditingController();
  final TextEditingController _headerCtrl = TextEditingController();
  String? _selectedApp;
  MnWsResponse? _response;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _methodCtrl.dispose();
    _pathCtrl.dispose();
    _bodyCtrl.dispose();
    _headerCtrl.dispose();
    super.dispose();
  }

  MnWsService get _svc => ref.read(mnWsServiceProvider);

  /// 主题色。做成 getter 而不是每个方法各取一次：
  /// 页面重建后主题可能变了（跟随系统），局部变量会拿着旧值。
  ColorScheme get _cs => Theme.of(context).colorScheme;

  /// 探一次服务 + 换凭据 + 拉目录。
  ///
  /// 探测结果必须落到界面上而不是只在日志里：服务端开着开关但连不上认证中心时，
  /// 不探的话用户看到的是「点了没反应」，探了才能一句话说清是谁的问题。
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ready = await _svc.readiness();
    if (!mounted) return;
    setState(() => _readiness = ready);
    if (!ready.available) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final apps = await _svc.catalog();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _selectedApp ??= apps.isEmpty ? null : apps.first.app;
        _loading = false;
      });
      await _loadRepos();
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// 显式重新授权（换一枚业务令牌）。
  Future<void> _reauthorize() async {
    setState(() {
      _authorizing = true;
      _error = null;
    });
    try {
      final grant = await _svc.ensureGrant(force: true);
      if (!mounted) return;
      setState(() {
        _authorizing = false;
        if (grant == null) {
          _error = '拿不到 mn-ws 凭据：请确认已登录统一登录平台';
        } else {
          _error = null;
        }
      });
      await _bootstrap();
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _authorizing = false;
        _error = e.message;
      });
    }
  }

  // ── 仓库 ────────────────────────────────────────────────────────────────

  Future<void> _loadRepos() async {
    if (_selectedApp != _repoApp) {
      // 当前没选 nx-kv：仓库页只在 nx-kv 下有意义，先清空而不是显示别人的数据
      if (mounted) setState(() => _repos = const []);
      return;
    }
    setState(() {
      _reposLoading = true;
      _repoError = null;
    });
    try {
      final res = await _svc.request(
        method: 'GET',
        path: '/api/repos',
        app: _repoApp,
      );
      final data = _dataOf(res.body);
      final list = <NxKvRepo>[];
      if (data is List) {
        for (final r in data.whereType<Map<String, dynamic>>()) {
          list.add(NxKvRepo.fromJson(r));
        }
      }
      if (!mounted) return;
      setState(() {
        _repos = list;
        _reposLoading = false;
      });
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _repoError = e.message;
        _reposLoading = false;
      });
    }
  }

  Future<void> _removeRepo(NxKvRepo repo) async {
    setState(() => _repoError = null);
    try {
      await _svc.request(
        method: 'DELETE',
        path: '/api/repos/${Uri.encodeComponent(repo.id)}',
        app: _repoApp,
      );
      await _loadRepos();
    } on MnWsException catch (e) {
      if (mounted) setState(() => _repoError = e.message);
    }
  }

  /// 登记一个仓库（路径 + 名称 + 描述）。
  Future<void> _addRepo() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) {
      setState(() => _repoError = '先填仓库路径');
      return;
    }
    setState(() => _repoError = null);
    try {
      await _svc.request(
        method: 'POST',
        path: '/api/repos',
        app: _repoApp,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path, 'desc': '经 mn-ws 登记'}),
      );
      _pathCtrl.clear();
      await _loadRepos();
    } on MnWsException catch (e) {
      if (mounted) setState(() => _repoError = e.message);
    }
  }

  // ── 请求台 ──────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final app = _selectedApp;
    if (app == null) {
      setState(() => _error = '先在「连接」里选一个应用');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _response = null;
    });
    try {
      final headers = <String, String>{};
      // 额外的头一行一个 `名: 值`。
      for (final line in _headerCtrl.text.split('\n')) {
        final s = line.trim();
        if (s.isEmpty) continue;
        final i = s.indexOf(':');
        if (i <= 0) continue;
        headers[s.substring(0, i).trim()] = s.substring(i + 1).trim();
      }
      final body = _bodyCtrl.text.trim();
      final res = await _svc.request(
        method: _methodCtrl.text.trim().isEmpty ? 'GET' : _methodCtrl.text.trim(),
        path: _pathCtrl.text.trim().isEmpty ? '/' : _pathCtrl.text.trim(),
        app: app,
        headers: headers,
        body: body.isEmpty ? null : body,
      );
      if (!mounted) return;
      setState(() {
        _response = res;
        _sending = false;
      });
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _sending = false;
      });
    }
  }

  /// 从 `{ok:true,data:...}` 信封里取 data；不是这个形状就返回整个 body 的解析结果。
  dynamic _dataOf(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _cs.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '连接'),
                Tab(text: '仓库'),
                Tab(text: '请求'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildConnectTab(),
                  _buildReposTab(),
                  _buildRequestTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab ① 连接 ────────────────────────────────────────────────────────

  Widget _buildConnectTab() {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub, size: 22, color: _cs.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'mn-ws 双向桥',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    MnWsConfig.baseUrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _statusLine(),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: _cs.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading || _authorizing
                            ? null
                            : () => _reauthorize(),
                        icon: _authorizing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.vpn_key),
                        label: const Text('授权 / 重取凭据'),
                        style: EmphasisButton.borderEmphasis(context, color: Colors.indigo),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : () => _bootstrap(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新目录'),
                        style: EmphasisButton.borderEmphasis(context, color: Colors.blue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务端支持的应用（${_apps.length}）',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '这一份是 server 半汇总的元信息目录：每个应用对应本机的一个端口。'
                    '选中之后，「仓库」与「请求」两个页签都走它。',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_apps.isEmpty)
                    const Text(
                      '目录为空 —— 桥那头还没有注册任何应用。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  else
                    ..._apps.map(_buildAppRow),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine() {
    final r = _readiness;
    if (r == null) {
      return const Text('探测中…', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    if (!r.available) {
      return Text(
        '不可用：${r.reason}',
        style: TextStyle(fontSize: 12, color: _cs.error),
      );
    }
    return const Text(
      '已连上 mn-ws · 凭据就绪',
      style: TextStyle(fontSize: 12, color: Colors.green),
    );
  }

  Widget _buildAppRow(MnWsApp app) {
    final selected = _selectedApp == app.app;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() => _selectedApp = app.app);
          if (app.app == _repoApp) _loadRepos();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? _cs.primaryContainer.withValues(alpha: 0.45)
                : Colors.grey.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _cs.primary : Colors.grey.withValues(alpha: 0.3),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: selected ? _cs.primary : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${app.app}  ·  端口 ${app.port ?? '—'}  ·  桥 ${app.bridgeId}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab ② 仓库（nx-kv）────────────────────────────────────────────────

  Widget _buildReposTab() {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'nx-kv 仓库管理（经桥）',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedApp == _repoApp
                        ? '请求头 X-Mn-Ws-App: $_repoApp —— 由 server 半转到本机 7877'
                        : '当前选中的应用不是 $_repoApp，先到「连接」页选它',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pathCtrl,
                          decoration: const InputDecoration(
                            labelText: '仓库路径',
                            hintText: 'D:\\code\\a_js\\proj\\nx-kv',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _selectedApp == _repoApp && !_reposLoading
                            ? () => _addRepo()
                            : null,
                        style: EmphasisButton.borderEmphasis(context, color: Colors.green),
                        child: const Text('登记'),
                      ),
                    ],
                  ),
                  if (_repoError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _repoError!,
                      style: TextStyle(fontSize: 12, color: _cs.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '已登记仓库',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _selectedApp == _repoApp && !_reposLoading
                            ? () => _loadRepos()
                            : null,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('刷新'),
                        style: EmphasisButton.borderEmphasis(context, color: Colors.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_reposLoading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_repos.isEmpty)
                    const Text(
                      '还没有仓库登记。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  else
                    ..._repos.map(_buildRepoRow),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepoRow(NxKvRepo repo) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repo.name.isEmpty ? repo.path : repo.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      repo.path,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移除登记',
                onPressed: () => _removeRepo(repo),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red,
              ),
            ],
          ),
          if (repo.desc.isNotEmpty)
            Text(repo.desc, style: const TextStyle(fontSize: 12)),
          if (repo.notes.isNotEmpty)
            Text(
              '备注：${repo.notes}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          if (repo.boards.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: repo.boards
                  .map((b) => Chip(
                        label: Text(b.name, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  // ── Tab ③ 请求台 ──────────────────────────────────────────────────────

  Widget _buildRequestTab() {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '内置请求台',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '走 X-Mn-Ws-App: ${_selectedApp ?? '（未选）'} —— '
                    'server 半据此决定转到本机哪个端口',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: TextField(
                          controller: _methodCtrl,
                          decoration: const InputDecoration(
                            labelText: '方法',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _pathCtrl,
                          decoration: const InputDecoration(
                            labelText: '路径',
                            hintText: '/api/repos',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _headerCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '额外请求头（一行一个「名: 值」）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bodyCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '请求体',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _sending ? null : () => _send(),
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('发送'),
                    style: EmphasisButton.borderEmphasis(context, color: Colors.green),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: _cs.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_response != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'HTTP ${_response!.status}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _response!.status < 400
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_response!.elapsed.inMilliseconds} ms',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _response!.body,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
