import 'package:flutter/material.dart';
import '../../surround_game_constants.dart';
import '../../_legacy/models/game_state.dart';

/// 围追堵截棋盘渲染 Widget
///
/// 接收 [GameState] 渲染网格棋盘。
/// [isHost] 控制颜色阵营。
class GameBoardWidget extends StatelessWidget {
  final GameState state;
  final bool isHost;

  const GameBoardWidget({
    super.key,
    required this.state,
    required this.isHost,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 24;
        final availableHeight = constraints.maxHeight - 24;
        final cellSize = (availableWidth / SurroundGameConstants.boardCols <
                availableHeight / SurroundGameConstants.boardRows)
            ? availableWidth / SurroundGameConstants.boardCols
            : availableHeight / SurroundGameConstants.boardRows;
        final actualCellSize = cellSize.clamp(6.0, 24.0);

        return Center(
          child: SizedBox(
            width: actualCellSize * SurroundGameConstants.boardCols,
            height: actualCellSize * SurroundGameConstants.boardRows,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount:
                  SurroundGameConstants.boardRows *
                  SurroundGameConstants.boardCols,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: SurroundGameConstants.boardCols,
              ),
              itemBuilder: (context, index) {
                final row = index ~/ SurroundGameConstants.boardCols;
                final col = index % SurroundGameConstants.boardCols;
                final cell = state.getCell(row, col);

                return Container(
                  margin: EdgeInsets.all(actualCellSize * 0.08),
                  decoration: BoxDecoration(
                    color: _cellColor(cell),
                    borderRadius: BorderRadius.circular(actualCellSize * 0.2),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Color _cellColor(CellState cell) {
    switch (cell) {
      case CellState.empty:
        return const Color(0xFFE8E8E8);
      case CellState.hostTrail:
        // Host 用蓝色，客机看对方轨迹也用蓝色
        return Colors.blue.withValues(alpha: 0.7);
      case CellState.clientTrail:
        // Client 用红色，主机看对方轨迹也用红色
        return Colors.red.withValues(alpha: 0.7);
      case CellState.wall:
        return const Color(0xFF424242);
    }
  }
}
