// lib/core/game_kit/lobby/_lobby_form.dart
//
// 入口表单的共享 widget —— smartMatch 与 dualEntry 渲染器复用同一份表单。
//
// 仅私有（同目录可见）；外部不导出。

import 'package:flutter/material.dart';

import '../../../services/lua/lua_game_alias.dart';
import 'game_lobby_spec.dart';

/// 表单 view-model（页内 state 透传）。
class LobbyFormState {
  final TextEditingController aliasCtrl;
  final TextEditingController codeCtrl;
  final bool busy;
  final String? error;

  const LobbyFormState({
    required this.aliasCtrl,
    required this.codeCtrl,
    required this.busy,
    required this.error,
  });
}

/// 入口表单 widget —— 由 GameLobbyPage 两个 flow 渲染器共用。
///
/// 内部逻辑：
///   · 昵称 / 房间号 字段（房间号支持随机号按钮 slot）
///   · formExtras 插槽（chess 残局 chip / team_card 随机号）
///   · 提示行（icon + 文本，位置由 spec.copy.hintPosition 决定）
///   · 主按钮 / 次按钮（dualEntry 才有次按钮）
///   · 错误 banner
///
/// 注意：本布局：颜色全部走 Theme.of(context).colorScheme + context.colors，
// 不再让调用方传入 BoardTheme/chessColors（消灭主题不一致）。
class LobbyForm extends StatefulWidget {
  final GameLobbySpec spec;
  final bool showSecondaryButton;
  final List<Widget> Function(BuildContext)? formExtras;

  final TextEditingController aliasCtrl;
  final TextEditingController codeCtrl;
  final bool busy;
  final String? error;

  /// 顶部主按钮点击（（smartMatch: 进入对局；dualEntry: 创建房间））
  final VoidCallback onPrimary;

  /// 顶部次按钮点击（仅 dualEntry: 加入房间）
  final VoidCallback? onSecondary;

  const LobbyForm({
    super.key,
    required this.spec,
    required this.aliasCtrl,
    required this.codeCtrl,
    required this.busy,
    required this.error,
    required this.onPrimary,
    this.onSecondary,
    this.formExtras,
    this.showSecondaryButton = false,
  });

  @override
  State<LobbyForm> createState() => _LobbyFormState();
}

class _LobbyFormState extends State<LobbyForm> {
  @override
  void initState() {
    super.initState();
    // 默认昵称填入（team_card: '玩家'）
    final defaultAlias = widget.spec.copy.defaultAlias;
    if (defaultAlias != null && widget.aliasCtrl.text.isEmpty) {
      widget.aliasCtrl.text = defaultAlias;
    }
    // 共享共享昵称回填 + notifier 监听（与 9 个游戏 LobbyEntryPage 行为一致）
    LuaGameAlias.load().then((v) {
      if (mounted && v.isNotEmpty && widget.aliasCtrl.text.isEmpty) {
        setState(() => widget.aliasCtrl.text = v);
      }
    });
    LuaGameAlias.notifier.addListener(_onAliasChanged);
  }

  @override
  void dispose() {
    LuaGameAlias.notifier.removeListener(_onAliasChanged);
    super.dispose();
  }

  void _onAliasChanged() {
    if (!mounted) return;
    final v = LuaGameAlias.value;
    if (v != widget.aliasCtrl.text) {
      setState(() => widget.aliasCtrl.text = v);
    }
  }

  void _generateRandomCode() {
    //  排除 0/O/1/I/L 的 6 位大写字母+数字
    // 从 '0O1IL' 中去掉所有易混字符后：A-Z 去 I L O + 数字去 0 1
    const pool =
        'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    final code = List<String>.generate(
      6,
      (i) => pool[(now + i * 31) % pool.length],
    ).join();
    setState(() => widget.codeCtrl.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = widget.spec.copy;
    final maxLen = widget.spec.maxCodeLength;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部标题区 —— hint 在上模式，插在最上方
              if (copy.hintPosition == HintPosition.top) ...[
                _HintCard(spec: widget.spec),
                const SizedBox(height: 16),
              ],
              Icon(
                widget.spec.heroIcon,
                size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                widget.spec.heroTagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),

              // 昵称字段
              TextField(
                controller: widget.aliasCtrl,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  labelText: '昵称',
                  hintText: copy.aliasFieldHint,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                onChanged: LuaGameAlias.save,
              ),
              const SizedBox(height: 12),

              // 房间号字段（可选随机号按钮 suffix）
              TextField(
                controller: widget.codeCtrl,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  labelText: '房间号',
                  hintText: copy.codeFieldHint,
                  prefixIcon: const Icon(Icons.tag),
                  suffixIcon: copy.randomCodeEnabled
                      ? IconButton(
                          icon: const Icon(Icons.casino_outlined),
                          tooltip: copy.randomCodeHint ?? '生成随机号',
                          onPressed: _generateRandomCode,
                        )
                      : null,
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: maxLen,
                onSubmitted: (_) =>
                    widget.busy ? null : widget.onPrimary(),
              ),
              const SizedBox(height: 4),

              // 游戏专属 extras（chess 残局 chip）
              if (widget.formExtras != null)
                ...widget.formExtras!(context),

              const SizedBox(height: 20),

              // 主按钮
              FilledButton(
                onPressed: widget.busy ? null : widget.onPrimary,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: widget.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        copy.primaryBtnText,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
              ),

              // 次按钮（仅 dualEntry）
              if (widget.showSecondaryButton &&
                  copy.secondaryBtnText != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: widget.busy ? null : widget.onSecondary,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    copy.secondaryBtnText!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 提示行（在下面）
              if (copy.hintPosition == HintPosition.bottom) _HintCard(spec: widget.spec),

              // 错误块
              if (widget.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 提示行小卡。
class _HintCard extends StatelessWidget {
  final GameLobbySpec spec;
  const _HintCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = spec.copy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              copy.hintIcon,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              copy.hintText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}