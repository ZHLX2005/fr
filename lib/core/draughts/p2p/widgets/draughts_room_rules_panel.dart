// lib/core/draughts/p2p/core/ui/draughts_room_rules_panel.dart
//
// 跳棋准备卡「房间规则」面板 —— 行样式对齐 ChessRoomRulesPanel。
//
// 只保留执子色三选（host_color）：白方永远先手（FMJD），无 first_mover；
// 残局 Lua 端已支持（initial_fen），客户端暂无残局库，本期不暴露入口。

import 'package:flutter/material.dart';

/// host/guest 执子色选择（random 由服务端立即解析为 w/b）。
enum DraughtsColorChoice { hostWhite, hostBlack, random }

/// 准备阶段规则面板 —— 可嵌入 lobby/ready 浮卡。
///
/// [editable]=true（房主）时点选即 [onChanged]；guest 只读展示当前规则。
class DraughtsRoomRulesPanel extends StatelessWidget {
  const DraughtsRoomRulesPanel({
    super.key,
    required this.editable,
    required this.hostColor,
    this.onChanged,
  });

  /// 房主可改；guest 只读。
  final bool editable;

  /// 当前服务端权威 host 执子色（'w' / 'b'；random 已在服务端解析）。
  final String hostColor;

  /// 房主改执子色时回调（'w' / 'b' / 'random'）。
  final ValueChanged<DraughtsColorChoice>? onChanged;

  DraughtsColorChoice get _colorChoice =>
      hostColor == 'b' ? DraughtsColorChoice.hostBlack : DraughtsColorChoice.hostWhite;

  void _emit(DraughtsColorChoice choice) {
    if (!editable || onChanged == null) return;
    onChanged!(choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editable ? '房间规则（仅房主可改）' : '房间规则',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        if (editable) ...[
          _colorRow(
            context,
            value: DraughtsColorChoice.hostWhite,
            icon: Icons.circle_outlined,
            label: '我执白，他执黑',
            sublabel: '（白方先手）',
          ),
          const SizedBox(height: 6),
          _colorRow(
            context,
            value: DraughtsColorChoice.hostBlack,
            icon: Icons.lens_outlined,
            label: '我执黑，他执白',
            sublabel: '（白方先手）',
          ),
          const SizedBox(height: 6),
          _colorRow(
            context,
            value: DraughtsColorChoice.random,
            icon: Icons.shuffle,
            label: '随机掷筛',
            sublabel: '（立即决定）',
            forceUnselected: true,
          ),
        ] else
          Text(
            _guestSummary(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
      ],
    );
  }

  String _guestSummary() {
    final hostSide = hostColor == 'b' ? '黑' : '白';
    return '房主执$hostSide；标准开局，白方先走。';
  }

  Widget _colorRow(
    BuildContext context, {
    required DraughtsColorChoice value,
    required IconData icon,
    required String label,
    required String sublabel,
    bool forceUnselected = false,
  }) {
    final theme = Theme.of(context);
    final selected = !forceUnselected && _colorChoice == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: editable ? () => _emit(value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (sublabel.isNotEmpty)
                      TextSpan(
                        text: '  $sublabel',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
