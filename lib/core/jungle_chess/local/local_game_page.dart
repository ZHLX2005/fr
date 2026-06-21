// lib/core/jungle_chess/local/local_game_page.dart
import 'package:flutter/material.dart';
import '../widgets/jungle_board.dart';
import '../widgets/jungle_board_frame.dart';
import '../widgets/jungle_touch_controller.dart';
import '../widgets/jungle_dialog.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'local_view_model.dart';
import 'local_match_state.dart';
import 'local_match_event.dart';

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

    final state = _viewModel.value;
    if (state is LocalFinished) {
      final gs = state.gameState;
      final winner = gs.winner;
      if (mounted) {
        showJungleGameOverDialog(
          context,
          winner == null ? '平局' : (winner == PlayerColor.blue ? '蓝方' : '红方'),
          gs.gameOverReason ?? '',
          onRestart: () => _viewModel.dispatch(const LocalResetRequested()),
          onExit: () => Navigator.pop(context),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text(
          '斗兽棋',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          _AppAction(
            icon: Icons.undo_rounded,
            tooltip: '悔棋',
            onPressed: () => _viewModel.dispatch(const LocalUndoRequested()),
          ),
          _AppAction(
            icon: Icons.refresh_rounded,
            tooltip: '重新开始',
            onPressed: () => _viewModel.dispatch(const LocalResetRequested()),
          ),
          _AppAction(
            icon: Icons.home_rounded,
            tooltip: '退出',
            onPressed: () async {
              if (mounted) {
                final exit = await showJungleExitConfirmDialog(context);
                if (exit && mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ValueListenableBuilder<LocalMatchState>(
        valueListenable: _viewModel,
        builder: (context, state, _) {
          return switch (state) {
            LocalIdle() => const _IdleScreen(),
            LocalInGame(:final gameState, :final currentPlayerIndex) =>
              _buildGameUI(gameState, currentPlayerIndex),
            LocalFinished(:final gameState) => _buildGameUI(gameState, -1),
          };
        },
      ),
    );
  }

  Widget _buildGameUI(GameState gameState, int currentPlayerIndex) {
    final isBlueTurn = currentPlayerIndex == 0;
    final isFinished = currentPlayerIndex == -1;
    return Column(
      children: [
        const SizedBox(height: 4),
        _TurnCard(
          isBlueTurn: isBlueTurn,
          isFinished: isFinished,
          round: gameState.roundCount ~/ 2 + 1,
          historyLen: gameState.history.length,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(
              child: AspectRatio(
                aspectRatio: 7 / 9,
                child: JungleBoardFrame(
                  child: JungleBoard(
                    gameState: gameState,
                    touchController: _touchController,
                    onMoveConfirmed: _onMoveConfirmed,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// === 私有组件 ===

class _AppAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _AppAction({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF4B5563)),
        onPressed: onPressed,
      ),
    );
  }
}

class _IdleScreen extends StatelessWidget {
  const _IdleScreen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('游戏已退出', style: TextStyle(color: Color(0xFF6B7280), fontSize: 16)),
    );
  }
}

class _TurnCard extends StatelessWidget {
  final bool isBlueTurn;
  final bool isFinished;
  final int round;
  final int historyLen;

  const _TurnCard({
    required this.isBlueTurn,
    required this.isFinished,
    required this.round,
    required this.historyLen,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isFinished
        ? const Color(0xFFFBBF24)
        : (isBlueTurn ? const Color(0xFF3B82F6) : const Color(0xFFEF4444));
    final bg = isFinished
        ? const Color(0xFFFFFBEB)
        : (isBlueTurn ? const Color(0xFFEFF6FF) : const Color(0xFFFEF2F2));
    final text = isFinished ? '对局结束' : (isBlueTurn ? '蓝方走棋' : '红方走棋');
    final emoji = isFinished ? '🏆' : (isBlueTurn ? '🔵' : '🔴');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(
                color: accent,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _MetaChip(label: '第 $round 回合'),
            const SizedBox(width: 6),
            _MetaChip(label: '$historyLen 步', muted: true),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool muted;
  const _MetaChip({required this.label, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}