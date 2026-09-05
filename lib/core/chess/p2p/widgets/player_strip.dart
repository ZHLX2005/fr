// lib/core/chess/p2p/widgets/player_strip.dart
//
// 对局中玩家条：圆形首字母头像 + 执子色点 + 名字/状态 + 可选 trailing（FAB）。
// 气泡叠在条内（对方在头像行下方、己方在头像行上方），不盖棋盘。

import 'package:flutter/material.dart';

import '../../models/piece.dart';

/// 棋盘上方（对手）/ 下方（自己）的玩家条。
class PlayerStrip extends StatelessWidget {
  final String alias;
  final PieceColor? color;
  final String subtitle;
  final bool isMe;
  final bool speaking;
  final Widget? trailing;
  final Widget? speech;

  const PlayerStrip({
    super.key,
    required this.alias,
    this.color,
    required this.subtitle,
    this.isMe = false,
    this.speaking = false,
    this.trailing,
    this.speech,
  });

  String get _initial {
    final t = alias.trim();
    if (t.isEmpty) return isMe ? '我' : '?';
    return String.fromCharCodes(t.runes.take(1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final row = Row(
      children: [
        _Avatar(
          initial: _initial,
          isMe: isMe,
          color: color,
          speaking: speaking,
          scheme: scheme,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                alias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );

    // 气泡贴头像侧：对方在条下方、己方在条上方（仍在 strip 布局内）
    final speechPad = speech == null
        ? null
        : Padding(
            padding: EdgeInsets.only(
              left: 50,
              top: isMe ? 0 : 6,
              bottom: isMe ? 6 : 0,
              right: 8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: speech!,
            ),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(14, isMe ? 4 : 8, 10, isMe ? 2 : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMe && speechPad != null) speechPad,
          row,
          if (!isMe && speechPad != null) speechPad,
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initial;
  final bool isMe;
  final PieceColor? color;
  final bool speaking;
  final ColorScheme scheme;

  const _Avatar({
    required this.initial,
    required this.isMe,
    required this.color,
    required this.speaking,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final fg = isMe
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return AnimatedScale(
      scale: speaking ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(
            color: speaking
                ? scheme.primary.withValues(alpha: 0.55)
                : (isMe
                    ? scheme.primary.withValues(alpha: 0.35)
                    : scheme.outlineVariant),
            width: speaking ? 2.4 : 1.6,
          ),
          boxShadow: speaking
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.22),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (color != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color == PieceColor.white
                        ? const Color(0xFFF7F4EE)
                        : const Color(0xFF2C261F),
                    border: Border.all(
                      color: scheme.surface,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
