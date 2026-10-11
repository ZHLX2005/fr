import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../../api/authhub/authhub_config.dart';
import '../../../api/authhub/authhub_exception.dart';
import '../../../api/providers/api_providers.dart';
import '../../../api/user/user_auth_service.dart';
import '../../../services/auth/auth_providers.dart';
import '../../../services/auth/unified_auth_service.dart';
import 'const_auth_login.dart';

/// 统一登录面板 —— 纯原生表单，不打开任何 WebView / 浏览器。
///
/// 三态：未登录（表单）、已登录（身份卡）、已过期（表单 + 预填账号）。
/// 把"过期"单独成一态而不是静默掉回未登录，是因为用户刚扫完码突然被要求
/// 重输一遍，界面若不说原因，他只会认为功能坏了。
class UnifiedLoginPanel extends ConsumerStatefulWidget {
  const UnifiedLoginPanel({super.key});

  @override
  ConsumerState<UnifiedLoginPanel> createState() => _UnifiedLoginPanelState();
}

class _UnifiedLoginPanelState extends ConsumerState<UnifiedLoginPanel> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  AuthSession? _session;
  bool _busy = false;
  bool _idpReachable = true;
  bool _expired = false;
  bool _needsReauth = false;
  String? _error;

  UnifiedAuthService get _svc => ref.read(unifiedAuthProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void dispose() {
    // 口令只活在这个 controller 里，随页面销毁一起清掉。
    _password.clear();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final reachable = await _svc.probeIdp();
    final session = reachable ? await _svc.restore() : null;
    if (!mounted) return;
    setState(() {
      _idpReachable = reachable;
      _session = session;
      _expired = false;
      _busy = false;
    });
    await _refreshReauthFlag();
  }

  Future<void> _refreshReauthFlag() async {
    final need = await ref.read(tokenManagerProvider).needsReauth;
    if (!mounted) return;
    setState(() => _needsReauth = need);
  }

  Future<void> _signIn() async {
    final u = _username.text.trim();
    final p = _password.text;
    if (u.isEmpty) {
      setState(() => _error = '请输入账号或邮箱');
      return;
    }
    if (p.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await _svc.signInWithPassword(username: u, password: p);
      if (!mounted) return;
      // 成功就抹掉口令：它已经换成 token 了，留在输入框里只是多一处泄露面
      _password.clear();
      setState(() {
        _session = session;
        _expired = false;
        _idpReachable = true;
        _busy = false;
      });
      await _refreshReauthFlag();
    } on AuthHubException catch (e) {
      if (!mounted) return;
      _password.clear();
      setState(() {
        _error = e.message;
        _busy = false;
        // 认证中心明确拒绝口令/账号，说明服务是通的；只有网络类错误才算不可达
        _idpReachable = e.error != AuthHubException.errNetwork &&
            e.error != AuthHubException.errDiscovery;
      });
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _svc.signOut();
    if (!mounted) return;
    setState(() {
      _session = null;
      _expired = false;
      _needsReauth = false;
      _busy = false;
    });
  }

  /// 令牌过期：回到表单，但把账号留下。
  Future<void> _reauth() async {
    final name = _session?.username ?? _session?.idp.preferredUsername ?? '';
    await _svc.signOut();
    if (!mounted) return;
    setState(() {
      _session = null;
      _expired = true;
      _needsReauth = false;
      if (name.isNotEmpty) _username.text = name;
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
          if (s != null)
            _SessionCard(session: s)
          else
            _LoginForm(
              username: _username,
              password: _password,
              busy: _busy,
              expired: _expired,
              onSubmit: _signIn,
            ),
          if (!_idpReachable) ...[
            const SizedBox(height: 12),
            _notice(context, scheme.error, AuthLoginConst.hintIdpUnreachable),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          if (s != null) ...[
            const SizedBox(height: 12),
            if (_needsReauth) ...[
              _notice(
                context,
                scheme.tertiary,
                '登录态已过期或即将过期。认证中心的 access_token 只有 10 分钟，'
                    '而客户端刻意不保存长期凭据，因此需要重新登录一次。',
              ),
              const SizedBox(height: 12),
            ],
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
                  child: _needsReauth
                      ? FilledButton(
                          onPressed: _busy ? null : _reauth,
                          child: const Text('重新登录'),
                        )
                      : FilledButton.tonal(
                          onPressed: _busy ? null : _signOut,
                          child: const Text(AuthLoginConst.btnSignOut),
                        ),
                ),
              ],
            ),
          ],
          const FallbackPasswordForm(),
        ],
      ),
    );
  }

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

/// 原生登录表单。
class _LoginForm extends StatelessWidget {
  final TextEditingController username;
  final TextEditingController password;
  final bool busy;
  final bool expired;
  final VoidCallback onSubmit;

  const _LoginForm({
    required this.username,
    required this.password,
    required this.busy,
    required this.expired,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              expired ? '登录已过期，请重新登录' : '统一登录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '认证中心 ${Uri.parse(AuthHubConfig.issuer).host}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: username,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '账号或邮箱',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                labelText: '密码',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: Text(busy ? '登录中…' : AuthLoginConst.btnSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已登录时的身份卡。
class _SessionCard extends StatelessWidget {
  final AuthSession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已登录：${s.displayName}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _kv(context, '认证中心', AuthHubConfig.issuer),
            _kv(context, 'sub', s.idp.sub),
            _kv(context, '邮箱', s.idp.email ?? '（未提供）'),
            _kv(context, '业务后端账号',
                s.backendUserId == null ? '未认领' : '#${s.backendUserId}'),
            _kv(context, '令牌到期',
                s.expiresAt.toLocal().toString().substring(0, 19)),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(k, style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(
              child: SelectableText(v,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
}

/// 邮箱密码登录（业务后端账号）—— 认证中心不可达时的降级路径。
///
/// 刻意做成折叠：默认收起，不让它在认证中心健康时抢主入口的注意力。
class FallbackPasswordForm extends ConsumerStatefulWidget {
  const FallbackPasswordForm({super.key});

  @override
  ConsumerState<FallbackPasswordForm> createState() =>
      _FallbackPasswordFormState();
}

class _FallbackPasswordFormState extends ConsumerState<FallbackPasswordForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _pwd.clear();
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
      // 走 GetIt 里的同一个实例：登录卡片、云同步面板用的都是它
      final r = await GetIt.instance<UserAuthService>()
          .login(_email.text.trim(), _pwd.text);
      if (!mounted) return;
      _pwd.clear();
      setState(() {
        _busy = false;
        _msg = r.isSuccess
            ? '已用业务后端账号登录（降级路径：无法批准扫码，那需要认证中心身份）'
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
                decoration:
                    const InputDecoration(labelText: '邮箱', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwd,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: '密码', isDense: true),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      _busy || _email.text.trim().isEmpty ? null : _submit,
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
