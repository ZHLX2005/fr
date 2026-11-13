import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/mnws/mnws.dart';
import '../../../core/ui/global/button/main.dart';
import '../../../core/ui/global/nav/main.dart';
import 'mnws_blocks.dart';

/// mn-ws 模块的**设置页**。
///
/// 这个模块后面会接越来越多的应用与配置项，所以先把「跟模块有关的东西」
/// 收在这一页里，而不是散在各个页面：
///   · 连的是哪台 server、用的是哪个身份
///   · 统一登录态与业务令牌各自的状态
///   · 白名单在哪配（在**电脑上**的 mn-ws 面板里，不是在手机上）
///   · 换令牌 / 退出
class MnWsSettingsPage extends ConsumerStatefulWidget {
  const MnWsSettingsPage({super.key});

  @override
  ConsumerState<MnWsSettingsPage> createState() => _MnWsSettingsPageState();
}

class _MnWsSettingsPageState extends ConsumerState<MnWsSettingsPage> {
  MnWsReadiness? _readiness;
  MnWsGrant? _grant;
  bool _busy = false;
  String? _error;

  MnWsService get _svc => ref.read(mnWsServiceProvider);

  ColorScheme get _cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final ready = await _svc.readiness();
    final grant = await ref.read(mnWsGrantStoreProvider).read();
    if (!mounted) return;
    setState(() {
      _readiness = ready;
      _grant = grant;
      _busy = false;
    });
  }

  Future<void> _reauthorize() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await _svc.ensureGrant(force: true);
      if (!mounted) return;
      if (g == null) {
        setState(() => _error = '没能换到令牌：可能统一登录态已过期，请先在 App 里登录。');
        return;
      }
      await _load();
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _svc.signOut();
    if (!mounted) return;
    setState(() {
      _grant = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    final ready = _readiness;
    final grant = _grant;

    return Scaffold(
      appBar: AppBar(title: const Text('mn-ws 设置')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
        children: [
          _section('连接', [
            _kv('server', MnWsConfig.baseUrl),
            _kv('认证中心', MnWsConfig.issuer),
            _kv('设备标识', MnWsConfig.deviceId),
            _kv('设备名', MnWsConfig.deviceName),
          ]),
          const SizedBox(height: 12),
          _section('凭据', [
            _kv(
              '统一登录态',
              ready == null
                  ? '（未探）'
                  : (ready.available ? '可用' : '不可用：${ready.reason}'),
            ),
            _kv(
              '业务令牌',
              grant == null
                  ? '未获得'
                  : (grant.isExpired ? '已过期' : '有效（${grant.userId}）'),
            ),
            if (grant != null && !grant.isExpired)
              _kv('到期', _expiryOf(grant.tokenExpiresAt)),
          ]),
          const SizedBox(height: 12),
          _section('白名单', [
            const Text(
              '要桥哪些服务是在**电脑上**配的，不是在手机上：\n'
              '  mn-ws apps set --apps my-api=http://127.0.0.1:9999\n'
              '或者在电脑上的 mn-ws 面板里「动态登记」。\n'
              '改完那边，这台手机刷新目录就能看到。',
              style: TextStyle(fontSize: 12),
            ),
          ]),
          const SizedBox(height: 12),
          if (_error != null)
            MnWsBlock(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, style: TextStyle(color: _cs.error)),
              ),
            ),
          MnWsBlock(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: EmphasisButton.borderEmphasis(
                            context,
                            color: _cs.primary,
                          ),
                          onPressed: _busy ? null : () => _reauthorize(),
                          child: const Text('重新换令牌'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: EmphasisButton.dangerEmphasis(context),
                          onPressed: _busy ? null : () => _signOut(),
                          child: const Text('清除业务令牌'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '「重新换令牌」会用当前的统一登录态静默换一枚新的业务令牌；'
                    '旧的那枚随即作废。',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return MnWsBlock(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(k, style: const TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );

  static String _expiryOf(int? ms) {
    if (ms == null || ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
