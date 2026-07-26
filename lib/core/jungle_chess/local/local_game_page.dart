// lib/core/jungle_chess/local/local_game_page.dart
//
// 本地热座对局页 —— 全屏、双方对称。
//
// 两位玩家面对面共用一台设备，所以页面**没有 AppBar、没有顶部回合卡**：
//   ┌───────────────────────┐
//   │ 红方面板（旋转 180°） │  ← 上方玩家正向阅读，悔棋按钮也转过去
//   ├───────────────────────┤
//   │        棋盘           │  ← 红方棋子图标恒定倒置
//   ├───────────────────────┤
//   │ 蓝方面板              │
//   ├───────────────────────┤
//   │ 返回 · 重开 · 教程    │
//   └───────────────────────┘
// "轮到谁走"由面板自身高亮表达（见 JunglePlayerPanel），不再单独占一条。
//
// 布局参考 lib/core/surround_game/local/local_game_page.dart。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/jungle_constants.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../tutorial/tutorial_page.dart';
import '../widgets/jungle_board.dart';
import '../widgets/jungle_board_frame.dart';
import '../widgets/jungle_dialog.dart';
import '../widgets/jungle_player_panel.dart';
import '../widgets/jungle_touch_controller.dart';
import 'local_match_event.dart';
import 'local_match_state.dart';
import 'local_view_model.dart';

class LocalGamePage extends StatefulWidget {
  const LocalGamePage({super.key});

  @override
  State<LocalGamePage> createState() => _LocalGamePageState();
}

class _LocalGamePageState extends State<LocalGamePage> {
  late final LocalViewModel _viewModel;
  late final JungleTouchController _touchController;

  @override
  void initState() {
    super.initState();
    _viewModel = LocalViewModel();
    _touchController = JungleTouchController();
    _viewModel.dispatch(const LocalStartPressed());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _touchController.dispose();
    super.dispose();
  }

  void _onMoveConfirmed(Coord from, Coord to) {
    _viewModel.dispatch(LocalMoveCommitted(from: from, to: to));
  }

  void _openTutorial() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JungleTutorialPage()),
    );
  }

  Future<void> _confirmExit() async {
    final nav = Navigator.of(context);
    final exit = await showJungleExitConfirmDialog(context);
    if (exit && mounted) nav.pop();
  }

  void _reset() {
    _touchController.clearSelection();
    _viewModel.dispatch(const LocalResetRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      body: SafeArea(
        child: ValueListenableBuilder<LocalMatchState>(
          valueListenable: _viewModel,
          builder: (_, state, _) {
            return switch (state) {
              LocalIdle() => const _IdleScreen(),
              LocalInGame(:final gameState) => _buildGameScreen(gameState),
              LocalFinished(:final gameState) => _buildGameScreen(
                  gameState,
                  overlay: _VictoryOverlay(
                    winner: gameState.winner,
                    reason: gameState.gameOverReason ?? '',
                    onRestart: _reset,
                    onExit: () => Navigator.pop(context),
                  ),
                ),
            };
          },
        ),
      ),
    );
  }

  Widget _buildGameScreen(GameState gs, {Widget? overlay}) {
    final finished = gs.isOver;

    // 存活子数 / 已吃子数（对方少掉的就是我吃掉的）
    var blueAlive = 0;
    var redAlive = 0;
    for (final p in gs.pieces.values) {
      if (!p.isAlive) continue;
      if (p.color == PlayerColor.blue) {
        blueAlive++;
      } else {
        redAlive++;
      }
    }

    // 悔棋归**刚走完那一步的人**：他的面板亮起悔棋按钮，等于"我走错了，收回来"。
    final lastMover = finished || gs.history.isEmpty
        ? null
        : (gs.currentTurn == PlayerColor.blue
            ? PlayerColor.red
            : PlayerColor.blue);
    VoidCallback? undoFor(PlayerColor c) => lastMover == c
        ? () {
            _touchController.clearSelection();
            _viewModel.dispatch(const LocalUndoRequested());
          }
        : null;

    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            JunglePlayerPanel(
              color: PlayerColor.red,
              rotated: true,
              isCurrent: !finished && gs.currentTurn == PlayerColor.red,
              aliveCount: redAlive,
              capturedCount: 8 - blueAlive,
              onUndo: undoFor(PlayerColor.red),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 7 / 9,
                    child: JungleBoardFrame(
                      child: JungleBoard(
                        gameState: gs,
                        touchController: finished ? null : _touchController,
                        onMoveConfirmed: _onMoveConfirmed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            JunglePlayerPanel(
              color: PlayerColor.blue,
              rotated: false,
              isCurrent: !finished && gs.currentTurn == PlayerColor.blue,
              aliveCount: blueAlive,
              capturedCount: 8 - redAlive,
              onUndo: undoFor(PlayerColor.blue),
            ),
            _BottomBar(
              onExit: _confirmExit,
              onReset: _reset,
              onTutorial: _openTutorial,
            ),
          ],
        ),
        ?overlay,
      ],
    );
  }
}

// ═══════════════════════ 私有组件 ═══════════════════════

class _IdleScreen extends StatelessWidget {
  const _IdleScreen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('游戏已退出',
          style: TextStyle(color: kTextMuted, fontSize: 16)),
    );
  }
}

/// 底部操作行 — 只对下方玩家正向（与 surround_game 一致）
class _BottomBar extends StatelessWidget {
  final VoidCallback onExit;
  final VoidCallback onReset;
  final VoidCallback onTutorial;

  const _BottomBar({
    required this.onExit,
    required this.onReset,
    required this.onTutorial,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kPanelHMargin, 10, kPanelHMargin, 10),
      child: Row(
        children: [
          Expanded(
            child: _BarButton(
              icon: Icons.arrow_back_rounded,
              label: '返回',
              tint: kTextNormal,
              onTap: onExit,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BarButton(
              icon: Icons.refresh_rounded,
              label: '重新开始',
              tint: kBluePieceTint,
              onTap: onReset,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BarButton(
              icon: Icons.menu_book_rounded,
              label: '教程',
              tint: const Color(0xFFD97706),
              onTap: onTutorial,
            ),
          ),
        ],
      ),
    );
  }
}

/// 边框强调式按钮：浅 tint 底 + 同色描边 + 同色前景
class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tint.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tint.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: tint,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 终局覆盖层。
///
/// 标题渲染两份：上半旋转 180°、下半正向 —— 面对面坐的两位玩家都能读到结果，
/// 操作按钮放在正中间，双方伸手都够得到。
class _VictoryOverlay extends StatelessWidget {
  final PlayerColor? winner;
  final String reason;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const _VictoryOverlay({
    required this.winner,
    required this.reason,
    required this.onRestart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final w = winner;
    final tint = w == null ? const Color(0xFFFBBF24) : playerTint(w);
    final title = w == null ? '平局' : '${playerName(w)} 获胜！';

    final headline = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events_rounded, size: 40, color: tint),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: tint,
          ),
        ),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(reason, style: const TextStyle(fontSize: 13, color: kTextMuted)),
        ],
      ],
    );

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 给上方玩家看的倒置副本
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationZ(math.pi),
                child: headline,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BarButton(
                    icon: Icons.refresh_rounded,
                    label: '再来一局',
                    tint: kBluePieceTint,
                    onTap: onRestart,
                  ),
                  const SizedBox(width: 12),
                  _BarButton(
                    icon: Icons.logout_rounded,
                    label: '退出',
                    tint: kTextNormal,
                    onTap: onExit,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              headline,
            ],
          ),
        ),
      ),
    );
  }
}
