import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/authhub/authhub_config.dart';
import '../../../api/authhub/authhub_exception.dart';
import '../../../api/user/user_auth_service.dart';
import '../../../services/auth/auth_providers.dart';
import '../../../services/auth/auth_webview_page.dart';
import '../../../services/auth/unified_auth_service.dart';
import 'const_auth_login.dart';

/// 统一登录面板：显示当前身份、发起/退出登录、认证中心可达性。
class UnifiedLoginPanel extends ConsumerStatefulWidget {
  const UnifiedLoginPanel({super.key});

  @override
  ConsumerState<UnifiedLoginPanel> createState() => _UnifiedLoginPanelState();
}

class _UnifiedLoginPanelState extends ConsumerState<UnifiedLoginPanel> {
  AuthSession? _session;
  bool _busy = false;
  bool _idpReachable = true;
  String? _error;
  bool _restored = false;

  UnifiedAuthService get _svc => ref.read(unifiedAuthProvider);

  @override
  void initState() {
    super.initState();
    // initState 里不能同步读 SharedPreferences / 网络，只能异步起一次。
    // 这里刻意不 await：面板要先画出来，登录态到了再刷新。
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final reachable = await _svc.probeIdp();
    final session = reachable ? await _svc.restore() : null;
    if (!mounted) return;
    setState(() {
      _idpReachable = reachable;
      _session = session;
      _busy = false;
      _restored = true;
    });
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await _svc.beginSignIn();
      if (!mounted) return;
      final host = Uri.parse(AuthHubConfig.issuer).host;
      final callback = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => AuthWebViewPage(
            authorizeUrl: request.authorizeUrl,
            redirectUri: request.redirectUri,
            identityHost: host,
          ),
        ),
      );
      if (callback == null) {
        // 用户主动取消是一种正常结局，不是错误：报"失败"会让人以为
        // 认证中心坏了，进而反复重试。
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = '已取消登录';
        });
        return;
      }
      final session = await _svc.completeSignIn(
        callbackUrl: callback,
        request: request,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _busy = false;
        _idpReachable = true;
      });
    } on AuthHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
        _idpReachable = e.error != AuthHubException.errDiscovery &&
            e.error != AuthHubException.errNetwork;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '登录失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _svc.signOut();
    if (!mounted) return;
    setState(() {
      _session = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _session;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s == null ? AuthLoginConst.hintNoSession : '已登录：${s.displayName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  _kv(context, '认证中心', AuthHubConfig.issuer),
                  _kv(context, 'client_id', AuthHubConfig.clientId),
                  if (s != null) ...[
                    _kv(context, 'sub', s.idp.sub),
                    _kv(context, 'email', s.idp.email ?? '（未提供）'),
                    _kv(context, '业务后端账号',
                        s.backendUserId == null ? '未认领' : '#${s.backendUserId}'),
                  ],
                  _kv(context, '认证中心可达', _idpReachable ? '是' : '否'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_idpReachable)
            _notice(context, scheme.error, AuthLoginConst.hintIdpUnreachable),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 16),
          if (s == null)
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: Text(_busy ? '处理中…' : AuthLoginConst.btnSignIn),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('刷新'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _busy ? null : _signOut,
                    child: const Text(AuthLoginConst.btnSignOut),
                  ),
                ),
              ],
            ),
          if (s == null) const FallbackPasswordForm(),
          if (_restored && s == null && _idpReachable) ...[
            const SizedBox(height: 14),
            Text(
              '登录后即可在「扫码批准」页批准其他设备；'
              '业务后端（dev_ctr_hello）现在也接受这张认证中心令牌，'
              '不再需要它自己的账号密码。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(k, style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );

  Widget _notice(BuildContext context, Color color, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// 邮箱密码登录（降级路径）。
///
/// 保留它的唯一理由：**认证中心是单点**。它一挂，如果本 App 只有统一登录
/// 一条路，那所有用户在故障期间连自己的数据都打不开 —— 这比"多一条老路径"
/// 的代价大得多。所以这条入口不是历史包袱，是刻意留的兜底。
///
/// 刻意做成折叠的：默认收起，不让它在认证中心健康时抢主入口的注意力。
class FallbackPasswordForm extends ConsumerStatefulWidget {
  const FallbackPasswordForm({super.key});

  @override
  ConsumerState<FallbackPasswordForm> createState() => _FallbackPasswordFormState();
}

class _FallbackPasswordFormState extends ConsumerState<FallbackPasswordForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _email.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      // 走 GetIt 里的同一个实例：登录卡片、云同步面板用的都是它，
      // 另起一个实例会带来第二套 token 读写路径。
      final r = await GetIt.instance<UserAuthService>()
          .login(_email.text.trim(), _pwd.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = r.isSuccess
            ? '已用业务后端账号登录（降级路径：扫码批准功能不可用）'
            : '登录失败：${r.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = '登录失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      title: Text('用业务后端账号登录（降级）',
          style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        '仅在认证中心不可达时使用。此路径不产生认证中心身份，因此无法批准扫码。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '邮箱', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwd,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码', isDense: true),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy || _email.text.trim().isEmpty ? null : _submit,
                  child: Text(_busy ? '登录中…' : '登录'),
                ),
              ),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_msg!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
