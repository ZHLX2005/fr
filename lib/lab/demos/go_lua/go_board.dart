// lib/lab/demos/go_lua/go_board.dart
//
// 围棋棋盘 widget — 9×9 网格线 + 交点落子。
//
// 与五子棋棋盘同构（网格线 + 交点落子），但：
//   - 尺寸 9×9（默认），星位为 9 路标准（4 角星，无天元）
//   - 支持 atari 高亮（被打吃群红描边）
//   - 棋子色：boardColors.player1Stone（深=黑）/ player2Stone（浅=白）
//
// 纯展示组件：棋盘状态通过构造函数传入，触摸交互由外层 GestureDetector 处理。

import 'package:flutter/material.dart';
import '../../../widgets/context_board_colors.dart';
import 'go_constants.dart' show kGoSize;
import 'go_engine.dart' show GoBoard;

/// 围棋棋盘绘制（网格线 + 星位 + 落子 + 最后一步 + 预览 + atari 高亮）。
///
/// [board]：9×9 状态，0=空/1=黑/2=白，索引 [y][x]。
/// [lastMove]：最后一步落子坐标（红点标记），可为 null。
/// [validMoves]：当前合法落点提示（半透明圆点）。
/// [previewPoint]：触摸悬停预览的交点（半透明子）。
/// [previewIsBlack]：预览子的颜色。
/// [atariPoints]：被打吃群棋子坐标集合（红描边高亮）。
class GoBoardWidget extends StatelessWidget {
  const GoBoardWidget({
    super.key,
    required this.board,
    this.lastMove,
    this.validMoves = const <(int, int)>{},
    this.previewPoint,
    this.previewIsBlack = true,
    this.atariPoints = const <(int, int)>{},
  });

  final GoBoard board;
  final (int, int)? lastMove;  // (x, y)
  final Set<(int, int)> validMoves;
  final (int, int)? previewPoint;
  final bool previewIsBlack;
  final Set<(int, int)> atariPoints;

  // 棋盘视觉参数
  static const double _padding = 16.0;

  /// 9 路标准星位（四角星，无天元——9 路奇数中点为星，但标准 9 路只有 4 角星）
  static const List<(int, int)> _starPoints = [
    (2, 2), (6, 2), (2, 6), (6, 6),
  ];

  @override
  Widget build(BuildContext context) {
    final bc = context.boardColors;
    final shadow = bc.scheme.onSurface.withValues(alpha: 0.15);
    final stoneShadow = bc.scheme.onSurface.withValues(alpha: 0.3);

    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.biggest.shortestSide;
      final gridSize = side - _padding * 2;
      final step = gridSize / (kGoSize - 1);
      final stoneRadius = step * 0.42;

      return SizedBox(
        width: side,
        height: side,
        child: Stack(clipBehavior: Clip.none, children: [
          // 棋盘背景（圆角米白 = boardColors.background）
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: bc.background,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: shadow, blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
            ),
          ),
          // 网格线 + 星位
          CustomPaint(
            size: Size.infinite,
            painter: _GridPainter(
              step: step,
              padding: _padding,
              lineColor: bc.gridLine,
              starPoints: _starPoints,
              starColor: bc.gridLine,
            ),
          ),
          // 落子
          for (int y = 0; y < kGoSize; y++)
            for (int x = 0; x < kGoSize; x++)
              if (board[y][x] != 0)
                _buildStone(
                  context, x, y, step, stoneRadius,
                  board[y][x] == 1,
                  isLast: lastMove == (x, y),
                  isAtari: atariPoints.contains((x, y)),
                  stoneShadow: stoneShadow,
                  stoneRim: bc.gridLine,
                ),
          // 合法落点提示（半透明圆点）
          for (final (x, y) in validMoves)
            _buildHintDot(x, y, step, bc.hint, stoneRadius * 0.3),
          // 预览子（触摸悬停）
          if (previewPoint != null)
            _buildStone(
              context, previewPoint!.$1, previewPoint!.$2, step, stoneRadius,
              previewIsBlack,
              isPreview: true,
              stoneShadow: stoneShadow,
              stoneRim: bc.gridLine,
            ),
        ]),
      );
    });
  }

  Widget _buildStone(
    BuildContext context,
    int x, int y, double step, double radius,
    bool isBlack, {
    bool isLast = false,
    bool isPreview = false,
    bool isAtari = false,
    required Color stoneShadow,
    required Color stoneRim,
  }) {
    final bc = context.boardColors;
    final cx = _padding + x * step;
    final cy = _padding + y * step;
    // 黑白两色跟主题：player1Stone（深）/ player2Stone（浅）
    final color = isBlack ? bc.player1Stone : bc.player2Stone;
    return Positioned(
      left: cx - radius,
      top: cy - radius,
      child: Opacity(
        opacity: isPreview ? 0.45 : 1.0,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isAtari
                ? Border.all(color: bc.errorMark, width: 2.0)  // 打吃红描边
                : Border.all(
                    color: isBlack ? stoneShadow : stoneRim,
                    width: isBlack ? 0.5 : 1.5,
                  ),
            boxShadow: isPreview ? [] : [
              BoxShadow(color: stoneShadow, blurRadius: 2, offset: const Offset(1, 1)),
            ],
          ),
          child: isLast
              ? Center(
                  child: Container(
                    width: radius * 0.5,
                    height: radius * 0.5,
                    decoration: BoxDecoration(
                      color: bc.lastMove,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildHintDot(int x, int y, double step, Color color, double radius) {
    final cx = _padding + x * step;
    final cy = _padding + y * step;
    return Positioned(
      left: cx - radius,
      top: cy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 网格线 + 星位绘制。
class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.step,
    required this.padding,
    required this.lineColor,
    required this.starPoints,
    required this.starColor,
  });

  final double step;
  final double padding;
  final Color lineColor;
  final List<(int, int)> starPoints;
  final Color starColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final n = kGoSize;
    for (var i = 0; i < n; i++) {
      final y = padding + i * step;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + (n - 1) * step, y),
        paint,
      );
    }
    for (var i = 0; i < n; i++) {
      final x = padding + i * step;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, padding + (n - 1) * step),
        paint,
      );
    }
    final starPaint = Paint()..color = starColor;
    const starRadius = 3.5;
    for (final (x, y) in starPoints) {
      final cx = padding + x * step;
      final cy = padding + y * step;
      canvas.drawCircle(Offset(cx, cy), starRadius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      step != oldDelegate.step ||
      lineColor != oldDelegate.lineColor ||
      starColor != oldDelegate.starColor;
}
