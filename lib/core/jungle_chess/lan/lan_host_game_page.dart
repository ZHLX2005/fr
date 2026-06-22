// lib/core/jungle_chess/lan/lan_host_game_page.dart
import 'package:flutter/material.dart';
import '../widgets/jungle_board.dart';
import '../widgets/jungle_board_frame.dart';
import '../widgets/jungle_touch_controller.dart';
import '../widgets/jungle_dialog.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'lan_host_view_model.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';

class LanHostGamePage extends StatefulWidget {
  final LanHostViewModel viewModel;
  const LanHostGamePage({super.key, required this.viewModel});

  @override
  State<LanHostGamePage> createState() => _LanHostGamePageState();
}

class _LanHostGamePageState extends State<LanHostGamePage> {
  late final JungleTouchController _touchController;

  @override
  void initState() {
    super.initState();
    _touchController = JungleTouchController();
    widget.viewModel.dispatch(const HostStartGame());
  }

  @override
  void dispose() {
    _touchController.dispose();
    super.dispose();
  }

  void _onMoveConfirmed(Coord from, Coord to) {
    widget.viewModel.dispatch(HostMoveCommitted(from: from, to: to));
    _checkGameOver();
  }

  void _checkGameOver() {
    final state = widget.viewModel.value;
    if (state is HostFinished && mounted) {
      final gs = state.gameState;
      showJungleGameOverDialog(
        context,
        gs.winner == null ? '平局' : (gs.winner == PlayerColor.blue ? '蓝方' : '红方'),
        gs.gameOverReason ?? '',
        onRestart: () => widget.viewModel.dispatch(const HostStartGame()),
        onExit: () => Navigator.pop(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text(
          '斗兽棋 · 主机',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ValueListenableBuilder<LanHostState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) {
          return switch (state) {
            HostLobby() => const _StateScreen(
                icon: Icons.hourglass_empty_rounded,
                title: '房间未创建',
              ),
            HostWaiting() => const _StateScreen(
                icon: Icons.wifi_tethering_rounded,
                title: '等待对手加入…',
              ),
            HostCountdown(:final secondsLeft) =>
              _StateScreen(icon: Icons.timer_outlined, title: '$secondsLeft'),
            HostInGame(:final gameState) => _buildGame(gameState, inGame: true),
            HostFinished(:final gameState) => _buildGame(gameState, inGame: false),
            HostError(:final message) => _StateScreen(
                icon: Icons.error_outline_rounded,
                title: '错误：$message',
                isError: true,
              ),
          };
        },
      ),
    );
  }

  Widget _buildGame(GameState gameState, {required bool inGame}) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _TurnCard(round: gameState.roundCount ~/ 2 + 1, historyLen: gameState.history.length),
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

class _TurnCard extends StatelessWidget {
  final int round;
  final int historyLen;
  const _TurnCard({required this.round, required this.historyLen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Text('🔵', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Text(
              '主机 · 蓝方',
              style: TextStyle(
                color: Color(0xFF3B82F6),
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

class _StateScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isError;
  const _StateScreen({required this.icon, required this.title, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: isError ? const Color(0xFFEF4444) : const Color(0xFF4B5563),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}