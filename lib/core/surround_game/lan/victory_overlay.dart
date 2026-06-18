// lib/core/surround_game/lan/victory_overlay.dart
//
// 游戏结束弹窗 — 全屏半透明遮罩 + 居中圆角对话框。
//
// 复用 local 模式视觉风格（见 local_game_page.dart:_buildVictoryOverlay），
// 但改为 LAN 场景的回调式 API（onRestart / onExit），不耦合 Navigator。
// 平局（draw）额外支持：标题色用中性 btnText，文案「平局」。

import 'package:flutter/material.dart';

import '../board_theme.dart';
import '../surround_game_constants.dart' show GameStatus;

/// 游戏结束遮罩层。
///
/// 根据 [status] 显示「上方获胜！」「下方获胜！」或「平局」，
/// 并提供「再来一局」与「返回」两个操作按钮。
/// 颜色全部取自 [theme]（BoardThemeData），与棋盘主题保持一致。
class VictoryOverlay extends StatelessWidget {
  final BoardThemeData theme;
  final GameStatus status;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const VictoryOverlay({
    super.key,
    required this.theme,
    required this.status,
    required this.onRestart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final isTopWin = status == GameStatus.topWin;
    final isDraw = status == GameStatus.draw;
    final winColor = isTopWin
        ? theme.piecePlayerA
        : (isDraw ? theme.btnText : theme.piecePlayerB);
    final winLabel = isTopWin
        ? '上方获胜！'
        : isDraw
            ? '平局'
            : '下方获胜！';

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: theme.panelBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events, size: 48, color: winColor),
              const SizedBox(height: 12),
              Text(
                winLabel,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: winColor,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: onRestart,
                    style: FilledButton.styleFrom(
                      backgroundColor: winColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('再来一局'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onExit,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.btnText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('返回'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
