import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../../api/authhub/authhub_config.dart';
import '../../../api/authhub/authhub_exception.dart';
import '../../../api/providers/api_providers.dart';
import '../../../api/remotetype/remotetype_models.dart';
import '../../../api/user/user_auth_service.dart';
import '../../../services/auth/auth_providers.dart';
import '../../../services/auth/unified_auth_service.dart';
import 'const_auth_login.dart';

/// 统一登录面板 —— 纯原生表单，并**分别展示两份凭据的状态**。
///
/// 界面上把两个凭据摊开显示不是啰嗦，而是这次架构修正的核心：
/// 上一版之所以会衍生出"refresh_token 要不要存""TTL 要不要调"这些问题，
/// 根因就是只有一个看不见的凭据在被同时当两样东西用。
/// 让"登录态"和"业务 token"各占一行，谁缺失、谁失效一眼可见，
/// 出问题时第一句排查的话也就有了落点。
class UnifiedLoginPanel extends ConsumerStatefulWidget {
  const UnifiedLoginPanel({super.key});

  @override
  ConsumerState<UnifiedLoginPanel> createState() => _UnifiedLoginPanelState();
}

class _UnifiedLoginPanelState extends ConsumerState<UnifiedLoginPanel> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  AppAuthState? _state;

  /// 远程输入桥（mn-rt）的凭据。与两份主凭据分开读：它的获取是懒式的
  /// （进「远程输入」页才铸），缺它不代表登录失败，只代表还没用到那个服务。
  RtGrant? _rtGrant;

  bool _busy = false;
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
    final state = await _svc.restore();
    // 只读本地磁盘（SharedPreferences），不发任何网络请求，失败就当没拿到
    final rt = await ref.read(remoteTypeGrantStoreProvider).read();
    if (!mounted) return;
    setState(() {
      _state = state;
      _rtGrant = rt;
      _busy = false;
    });
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
      final state = await _svc.signInWithPassword(username: u, password: p);
      if (!mounted) return;
      // 成功就抹掉口令：它已经换成登录态了，留在输入框里只是多一处泄露面
      _password.clear();
      setState(() {
        _state = state;
        _busy = false;
        // 登录态拿到了但业务 token 没换到，是一句需要单独说的告警：
        // 它意味着业务接口暂时不可用，而用户会以为登录彻底失败了。
        _error = state.hasIdpSession && !state.hasBackendToken
            ? '已拿到统一登录平台登录态，但换取业务后端令牌失败。'
                '业务接口暂不可用，可点「重试换令牌」再来一次。'
            : null;
      });
    } on AuthHubException catch (e) {
      if (!mounted) return;
      _password.clear();
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  Future<void> _retryMint() async {
    setState(() => _busy = true);
    final ok = await _svc.reauthBackendToken();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : '换取业务后端令牌仍然失败，请确认业务后端可达';
      _state = ok ? _state : _state;
    });
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await _svc.signOut();
    // 远程输入令牌也是这次登录的产物，退出时一起清：
    // 换账号登录后留着一枚旧账号的令牌，列表会串到别人（旧自己）的电脑。
    await ref.read(remoteTypeGrantStoreProvider).clear();
    if (!mounted) return;
    setState(() {
      _state = null;
      _rtGrant = null;
      _busy = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _state;
    final signedIn = s != null && s.hasIdpSession;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (signedIn)
            _CredentialCard(state: s!, rtGrant: _rtGrant)
          else
            _LoginForm(
              username: _username,
              password: _password,
              busy: _busy,
              onSubmit: _signIn,
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          if (signedIn) ...[
            const SizedBox(height: 14),
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
                  child: OutlinedButton(
                    onPressed: _busy ? null : _retryMint,
                    child: const Text('重试换令牌'),
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
          ],
          const FallbackPasswordForm(),
        ],
      ),
    );
  }
}

/// 三份凭据各自的状态。
class _CredentialCard extends StatelessWidget {
  final AppAuthState state;

  /// 远程输入桥（mn-rt）的凭据；null = 还没获得（懒式获取，不算异常）。
  final RtGrant? rtGrant;

  const _CredentialCard({required this.state, this.rtGrant});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = state;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已登录：${s.displayName}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row(
              context,
              label: '统一登录平台登录态',
              value: '有效',
              ok: true,
              hint: '用于批准扫码，以及静默换取业务后端令牌',
            ),
            _row(
              context,
              label: '业务后端令牌',
              value: s.hasBackendToken ? '已获得' : '未获得',
              ok: s.hasBackendToken,
              hint: s.hasBackendToken
                  ? '用于所有业务接口；失效时会自动用登录态重铸'
                  : '业务接口暂不可用，可点「重试换令牌」',
            ),
            ..._remoteTypeRow(context),
            if (s.idp != null) ...[
              const Divider(height: 24),
              _kv(context, '认证中心', AuthHubConfig.issuer),
              _kv(context, '账号', s.idp!.username),
              _kv(context, '邮箱', s.idp!.email.isEmpty ? '（未提供）' : s.idp!.email),
            ],
            if (s.rebound) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.10),
                  border: Border.all(color: scheme.tertiary),
                  borderRadius: BorderRadius.circular(8),
                ),
                // 改绑是用户能感知到"数据换了一个账号"的写操作，必须显式说出来。
                // 后端刻意把它回带上来而不是静默迁移，就是因为静默改绑
                // 会被用户当成丢数据。
                child: Text(
                  '注意：统一登录平台的身份本次被改绑到了另一个业务后端账号，'
                  '你看到的数据可能随之变化。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (s.provisioned) ...[
              const SizedBox(height: 8),
              Text('（业务后端原本没有这个邮箱的账号，本次已自动建档）',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  /// 远程输入令牌那一行。它不像业务令牌那样登录即铸，而是进对应页面时懒式获取，
  /// 所以「未获得」是正常态，提示语要说清去哪一步会拿到，别让人以为出了故障。
  List<Widget> _remoteTypeRow(BuildContext context) {
    final g = rtGrant;
    if (g == null) {
      return [
        _row(
          context,
          label: '远程输入令牌（mn-rt）',
          value: '未获得',
          ok: false,
          hint: '进入「远程输入」页时会用登录态自动获取',
        ),
      ];
    }
    final expired = g.isExpired;
    return [
      _row(
        context,
        label: '远程输入令牌（mn-rt）',
        value: expired ? '已过期' : '已获得${_expirySuffix(g.expiresAtMs)}',
        ok: !expired,
        hint: expired
            ? '进入「远程输入」页时会自动重取'
            : '用于「远程输入」连接我的电脑；失效时会自动用登录态重铸',
      ),
    ];
  }

  /// 到期时间后缀。服务端 365 天有效期，给个日子比给秒数有用。
  String _expirySuffix(int expiresAtMs) {
    if (expiresAtMs <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    final two = (int n) => n.toString().padLeft(2, '0');
    return '（${t.year}-${two(t.month)}-${two(t.day)} 到期）';
  }

  Widget _row(BuildContext context,
      {required String label,
      required String value,
      required bool ok,
      required String hint}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: ok ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ok ? null : scheme.error,
                      )),
            ],
          ),
          const SizedBox(height: 2),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
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
              width: 88,
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

/// 原生登录表单。
class _LoginForm extends StatelessWidget {
  final TextEditingController username;
  final TextEditingController password;
  final bool busy;
  final VoidCallback onSubmit;

  const _LoginForm({
    required this.username,
    required this.password,
    required this.busy,
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
            Text('统一登录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('认证中心 ${Uri.parse(AuthHubConfig.issuer).host}',
                style: Theme.of(context).textTheme.bodySmall),
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
            const SizedBox(height: 8),
            Text(
              '登录后同时获得两份凭据：统一登录平台的登录态，'
              '以及业务后端的访问令牌（后者由前者静默换取，无需再次输入口令）。',
              style: Theme.of(context).textTheme.bodySmall,
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

/// 邮箱密码登录（业务后端账号）—— 认证中心不可达时的降级路径。
///
/// 折叠放置：默认收起，不让它在认证中心健康时抢主入口的注意力。
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
      // 走 GetIt 里的同一个实例：登录卡片、云同步面板用的是同一个
      final r = await GetIt.instance<UserAuthService>()
          .login(_email.text.trim(), _pwd.text);
      if (!mounted) return;
      _pwd.clear();
      setState(() {
        _busy = false;
        _msg = r.isSuccess
            ? '已用业务后端账号登录（降级路径：没有统一登录平台登录态，'
                '因此无法批准扫码）'
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
        '仅在认证中心不可达时使用。此路径不产生登录态，因此无法批准扫码。',
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
