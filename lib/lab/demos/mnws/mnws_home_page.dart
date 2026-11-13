import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/mnws/mnws.dart';
import '../../../core/ui/global/button/main.dart';
import '../../../core/ui/global/nav/main.dart';
import 'mnws_app_views.dart';
import 'mnws_request_page.dart';
import 'mnws_settings_page.dart';

/// mn-ws 的**首页**：哪几台电脑接上来了，每台上跑着什么。
///
/// ## 为什么按 PC 分组
///
/// 桥接的价值是「把好几台机器上的服务都摆到手机面前」。目录如果只是一长串
/// 应用，用户得自己猜「这条是哪个机器上的」；按 PC 分组之后，
/// 先看电脑、再看它上面的应用 —— 这也正是「多 client 同时运行」时
/// 唯一说得清的呈现方式。
class MnWsHomePage extends ConsumerStatefulWidget {
  const MnWsHomePage({super.key});

  @override
  ConsumerState<MnWsHomePage> createState() => _MnWsHomePageState();
}

class _MnWsHomePageState extends ConsumerState<MnWsHomePage> {
  MnWsReadiness? _readiness;
  MnWsCatalog _catalog = const MnWsCatalog();
  bool _loading = true;
  bool _authorizing = false;
  String? _error;

  MnWsService get _svc => ref.read(mnWsServiceProvider);

  ColorScheme get _cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

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
      final cat = await _svc.catalog();
      if (!mounted) return;
      setState(() {
        _catalog = cat;
        _loading = false;
      });
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
      final g = await _svc.ensureGrant(force: true);
      if (!mounted) return;
      if (g == null) {
        setState(() => _error = '没能换到 mn-ws 的令牌：可能统一登录态已过期，先去登录。');
        return;
      }
      await _bootstrap();
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _authorizing = false);
    }
  }

  void _openApp(MnWsPcGroup pc, MnWsPcApp app) {
    final target = MnWsAppTarget(pc: pc, pcApp: app);
    final view = appViewOf(app.app);
    // 认得的应用 → 给它专门的整页；不认得的 → 通用请求台
    final page = view == null
        ? MnWsRequestPage(target: target)
        : view.builder(context, target);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('mn-ws 桥接'),
        actions: [
          IconButton(
            tooltip: '请求台',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MnWsRequestPage(),
              ),
            ),
            icon: const Icon(Icons.terminal_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MnWsSettingsPage(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _bootstrap(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
          children: [
            _statusCard(),
            const SizedBox(height: 16),
            ..._pcCards(),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final ready = _readiness;
    if (ready != null && !ready.available) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('还不能用', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(ready.reason, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              OutlinedButton(
                style: EmphasisButton.borderEmphasis(context, color: _cs.primary),
                onPressed: _authorizing ? null : () => _reauthorize(),
                child: Text(_authorizing ? '换令牌中…' : '重新换令牌'),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('拉目录失败', style: TextStyle(color: _cs.error)),
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              OutlinedButton(
                style: EmphasisButton.borderEmphasis(context, color: _cs.primary),
                onPressed: _authorizing ? null : () => _reauthorize(),
                child: Text(_authorizing ? '换令牌中…' : '重新换令牌'),
              ),
            ],
          ),
        ),
      );
    }
    final pcCount = _catalog.pcs.length;
    final appCount = _catalog.count;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lan_outlined, color: _cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                pcCount == 0
                    ? '还没有 PC 接入'
                    : '已接入 $pcCount 台 PC，共 $appCount 个应用',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _authorizing ? null : () => _reauthorize(),
              child: Text(_authorizing ? '换令牌中…' : '换令牌'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _pcCards() {
    if (_catalog.pcs.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _catalog.apps.isEmpty
                  ? '没有应用。在电脑上跑 `mn-ws apps add <名字> --port <端口>` 登记一个，'
                      '它就会出现在这里。'
                  : '服务端返回的是旧格式目录（没有 PC 分组）。',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ];
    }
    return _catalog.pcs.map((pc) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.computer_outlined, size: 18, color: _cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pc.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    pc.bridgeId,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (pc.apps.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text('这台电脑没有登记应用', style: TextStyle(fontSize: 12)),
              )
            else
              ...pc.apps.map((a) {
                final view = appViewOf(a.app);
                return ListTile(
                  dense: true,
                  title: Row(
                    children: [
                      Text(a.title),
                      if (a.title != a.app)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            a.app,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      if (!a.active)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _tag('路由在别的 PC 上', _cs.error),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    view == null
                        ? '未识别的应用 · 点开用请求台调它'
                        : view.description,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _openApp(pc, a),
                );
              }),
          ],
        ),
      );
    }).toList();
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 10, color: color),
        ),
      );
}
