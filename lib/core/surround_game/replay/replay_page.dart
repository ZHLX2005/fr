// 只读回放页：复用 ChessBoard/ChessWall/ChessPlayer 渲染光标处棋盘 + 传输条。
// 无 TouchView / 无确认操作 / 无合法落子提示 —— 纯观察。
import 'package:flutter/material.dart';

import '../board_theme.dart';
import '../models/game_state.dart';
import 'replay_controller.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_player.dart';
import '../widgets/chess_wall.dart';

class ReplayPage extends StatefulWidget {
  final List<MoveRecord> history;
  const ReplayPage({super.key, required this.history});

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  late final ReplayController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReplayController(history: widget.history);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('回放'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final cellSize = w / 11;
                    return ValueListenableBuilder<ReplayState>(
                      valueListenable: _controller.stateNotifier,
                      builder: (context, rs, _) {
                        final gs = rs.board;
                        return SizedBox(
                          width: w,
                          height: w,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ChessBoard(cellSize: cellSize, theme: theme),
                              ChessWall(
                                history: gs.history,
                                cellSize: cellSize,
                                theme: theme,
                              ),
                              ChessPlayer(
                                cellId: gs.topPlayerId,
                                cellSize: cellSize,
                                color: theme.piecePlayerA,
                              ),
                              ChessPlayer(
                                cellId: gs.bottomPlayerId,
                                cellSize: cellSize,
                                color: theme.piecePlayerB,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            ValueListenableBuilder<ReplayState>(
              valueListenable: _controller.stateNotifier,
              builder: (context, rs, _) => _TransportBar(
                state: rs,
                controller: _controller,
                theme: theme,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 传输条：步数/回合 + 按钮行 + scrub 滑块。
class _TransportBar extends StatelessWidget {
  final ReplayState state;
  final ReplayController controller;
  final BoardThemeData theme;

  const _TransportBar({
    required this.state,
    required this.controller,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.panelBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('第 ${state.cursor} / ${state.totalMoves} 手',
                  style: TextStyle(
                      color: theme.btnText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(state.board.currentPlayerIsTop ? '上方回合' : '下方回合',
                  style: TextStyle(color: theme.btnSub, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.skip_previous, '到头', controller.jumpToStart,
                  disabled: state.atStart),
              const SizedBox(width: 12),
              _btn(Icons.chevron_left, '上一步', controller.stepBackward,
                  disabled: state.atStart),
              const SizedBox(width: 12),
              _btn(
                state.isPlaying ? Icons.pause : Icons.play_arrow,
                state.isPlaying ? '暂停' : '播放',
                controller.togglePlay,
                disabled: state.atEnd,
                primary: true,
              ),
              const SizedBox(width: 12),
              _btn(Icons.chevron_right, '下一步', controller.stepForward,
                  disabled: state.atEnd),
              const SizedBox(width: 12),
              _btn(Icons.skip_next, '到尾', controller.jumpToEnd,
                  disabled: state.atEnd),
              const Spacer(),
              GestureDetector(
                onTap: controller.cycleSpeed,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.btnBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.btnBorder),
                  ),
                  child: Text(_speedLabel(state.speed),
                      style: TextStyle(
                          color: theme.btnText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.totalMoves > 0)
            Slider(
              min: 0,
              max: state.totalMoves.toDouble(),
              divisions: state.totalMoves,
              value: state.cursor.toDouble(),
              onChanged: (v) => controller.seek(v.round()),
              activeColor: theme.piecePlayerA,
              inactiveColor: theme.btnBorder,
            )
          else
            const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _speedLabel(ReplaySpeed s) {
    switch (s) {
      case ReplaySpeed.x1:
        return '1x';
      case ReplaySpeed.x2:
        return '2x';
      case ReplaySpeed.x4:
        return '4x';
    }
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool disabled = false, bool primary = false}) {
    final color = primary ? theme.piecePlayerA : theme.btnText;
    return Opacity(
      opacity: disabled ? 0.35 : 1.0,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
