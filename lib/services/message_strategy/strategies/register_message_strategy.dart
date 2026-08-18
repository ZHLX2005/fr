import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../interfaces/interfaces.dart';
import '../data/register_message_data.dart';
import '../panel/register_flow_controller.dart';
import '../../../api/user/user_auth_service.dart';
import '../../../core/design/emphasis_button.dart';

/// Strategy for rendering Register messages.
///
/// type 统一 `'register'`，按 [RegisterMessageData.step] 渲染对应步骤卡。
/// 流程推进由 [RegisterFlowController] 负责；本策略只管每步的输入与错误展示。
/// code/password/invite 步带「上一步」按钮调 flow.back()。
class RegisterMessageWidgetStrategy
    extends MessageWidgetStrategy<RegisterMessageData> {
  @override
  Widget build(BuildContext context, RegisterMessageData data) {
    switch (data.step) {
      case RegisterStep.email:
        return const _EmailStep();
      case RegisterStep.code:
        return const _CodeStep();
      case RegisterStep.password:
        return const _PasswordStep();
      case RegisterStep.invite:
        return const _InviteStep();
      case RegisterStep.success:
        return const _SuccessStep();
    }
  }

  @override
  RegisterMessageData createMockData() =>
      const RegisterMessageData(RegisterStep.email);
}

/// 「上一步」按钮：调全局 flow 回退
Widget _backButton({VoidCallback? onPressed}) {
  return OutlinedButton(
    onPressed: onPressed ?? () => GetIt.instance<RegisterFlowController>().back(),
    child: const Text('上一步'),
  );
}

/// 通用步骤卡外框
Widget _stepShell(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<Widget> children,
}) {
  final theme = Theme.of(context);
  return Container(
    constraints: const BoxConstraints(maxWidth: 320),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.tertiary),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

Widget _errorText(BuildContext context, String? error) {
  if (error == null) return const SizedBox.shrink();
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      error,
      style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
    ),
  );
}

// ── 步骤 1：邮箱 + 发送验证码（60s 冷却倒计时）──────────────────────
class _EmailStep extends StatefulWidget {
  const _EmailStep();
  @override
  State<_EmailStep> createState() => _EmailStepState();
}

class _EmailStepState extends State<_EmailStep> {
  final _emailCtrl = TextEditingController();
  bool _sent = false;
  bool _sending = false;
  int _countdown = 0;
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  Future<void> _onSend() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请输入邮箱');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    // 首次经 flow（成功会 append 验证码步）；重发直接调 service，不再 append
    final AuthResult r;
    if (!_sent) {
      r = await GetIt.instance<RegisterFlowController>().sendCode(email);
    } else {
      r = await GetIt.instance<UserAuthService>().sendCode(email);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.isSuccess) {
      setState(() => _sent = true);
      _startCountdown();
    } else {
      setState(() => _error = r.message.isEmpty ? '发送失败' : r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _stepShell(
      context,
      icon: Icons.email_outlined,
      title: '注册 · 邮箱',
      children: [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          readOnly: _sent,
          decoration: const InputDecoration(
            labelText: '邮箱',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '验证码 6 位、10 分钟有效',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: EmphasisButton.borderEmphasis(
            context,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: (_sending || (_sent && _countdown > 0)) ? null : _onSend,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_sent ? Icons.refresh : Icons.send),
          label: Text(_sent
              ? (_countdown > 0 ? '${_countdown}s 后可重发' : '重新发送')
              : '发送验证码'),
        ),
        _errorText(context, _error),
      ],
    );
  }
}

// ── 步骤 2：验证码 ─────────────────────────────────────────────────
class _CodeStep extends StatefulWidget {
  const _CodeStep();
  @override
  State<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<_CodeStep> {
  final _codeCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    GetIt.instance<RegisterFlowController>().submitCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _stepShell(
      context,
      icon: Icons.password_outlined,
      title: '注册 · 验证码',
      children: [
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '验证码',
            border: OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _backButton(),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: EmphasisButton.borderEmphasis(
                  context,
                  color: theme.colorScheme.primary,
                ),
                onPressed: _confirm,
                child: const Text('下一步：设置密码'),
              ),
            ),
          ],
        ),
        _errorText(context, _error),
      ],
    );
  }
}

// ── 步骤 3：密码 ──────────────────────────────────────────────────
class _PasswordStep extends StatefulWidget {
  const _PasswordStep();
  @override
  State<_PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<_PasswordStep> {
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final pwd = _pwdCtrl.text;
    if (pwd.length < 6) {
      setState(() => _error = '密码至少 6 位');
      return;
    }
    if (pwd != _confirmCtrl.text) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    GetIt.instance<RegisterFlowController>().submitPassword(pwd);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _stepShell(
      context,
      icon: Icons.lock_outline,
      title: '注册 · 密码',
      children: [
        TextField(
          controller: _pwdCtrl,
          obscureText: _obscure,
          decoration: const InputDecoration(
            labelText: '密码（≥6 位）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '确认密码',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _backButton(),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: EmphasisButton.borderEmphasis(
                  context,
                  color: theme.colorScheme.primary,
                ),
                onPressed: _confirm,
                child: const Text('下一步：邀请码'),
              ),
            ),
          ],
        ),
        _errorText(context, _error),
      ],
    );
  }
}

// ── 步骤 4：邀请码（必填）+ 昵称（可选）→ 注册 ─────────────────────
class _InviteStep extends StatefulWidget {
  const _InviteStep();
  @override
  State<_InviteStep> createState() => _InviteStepState();
}

class _InviteStepState extends State<_InviteStep> {
  final _inviteCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _inviteCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final invite = _inviteCtrl.text.trim();
    if (invite.isEmpty) {
      setState(() => _error = '邀请码必填（没有可用引导码 ROOT-INIT-2026）');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await GetIt.instance<RegisterFlowController>()
        .register(invite, _nickCtrl.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (!r.isSuccess) {
      setState(() => _error = r.message.isEmpty ? '注册失败' : r.message);
    }
    // 成功时 flow 已 append 成功步
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _stepShell(
      context,
      icon: Icons.card_giftcard,
      title: '注册 · 邀请码',
      children: [
        TextField(
          controller: _inviteCtrl,
          decoration: const InputDecoration(
            labelText: '邀请码（必填）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nickCtrl,
          decoration: const InputDecoration(
            labelText: '昵称（可选）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _backButton(
              onPressed: _loading
                  ? null
                  : () => GetIt.instance<RegisterFlowController>().back(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: EmphasisButton.borderEmphasis(
                  context,
                  color: theme.colorScheme.primary,
                ),
                onPressed: _loading ? null : _register,
                child: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      )
                    : const Text('提交注册'),
              ),
            ),
          ],
        ),
        _errorText(context, _error),
      ],
    );
  }
}

// ── 步骤 5：成功 ──────────────────────────────────────────────────
class _SuccessStep extends StatelessWidget {
  const _SuccessStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flow = GetIt.instance<RegisterFlowController>();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '注册成功${flow.userId != null ? "（userId=${flow.userId}）" : ""}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: flow.gotoLogin,
            icon: Icon(Icons.login),
            label: const Text('去登录'),
          ),
        ],
      ),
    );
  }
}
