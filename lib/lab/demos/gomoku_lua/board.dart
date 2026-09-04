// lib/lab/demos/gomoku_lua/board.dart
//
// 五子棋棋盘 widget — 15x15 网格线 + 交点落子。
//
// 与围追堵截的格子棋盘不同：五子棋落子在**线条交点**上，
// 所以绘制方式是"先画网格线，再在交点画棋子"。
//
// 颜色策略（v6.2）：
//   · 棋盘 UI 色（底/网格/星位/红点/提示）→ context.boardColors
//   · 黑白棋子本体色 → boardColors.player1Stone / player2Stone
//     （切到任意主题自动跟：zen 米底+暖墨黑子/米白子，深色主题+白子/深子）
//   · 阴影/遮罩 → boardColors.scheme.onSurface 半透叠加
//
// 纯展示组件：棋盘状态通过构造函数传入，触摸交互由外层 GestureDetector 处理。

import 'package:flutter/material.dart';

import '../../../widgets/context_board_colors.dart';
import 'constants.dart' show kGomokuSize;
import 'engine.dart' show GomokuBoard;
import '../../../core/gomoku/skins/gomoku_skin.dart' show GomokuSkin;

/// 五子棋棋盘绘制（网格线 + 星位 + 落子 + 最后一步标记 + 落点提示）。
///
/// [board]：15x15 状态，0=空/1=黑/2=白，索引 [y][x]。
/// [lastMove]：最后一步落子坐标（用于红点标记），可为 null。
/// [validMoves]：当前合法落点提示（半透明圆点），可为空集合。
/// [previewPoint]：触摸悬停预览的交点（半透明子），可为 null。
/// [previewIsBlack]：预览子的颜色。
class GomokuBoardWidget extends StatelessWidget {
  const GomokuBoardWidget({
    super.key,
    required this.board,
    required this.lastMove,
    this.validMoves = const <(int, int)>{},
    this.previewPoint,
    this.previewIsBlack = true,
    this.skin,
  });

  final GomokuBoard board;
  final (int, int)? lastMove;  // (x, y)
  final Set<(int, int)> validMoves;
  final (int, int)? previewPoint;
  final bool previewIsBlack;
  final GomokuSkin? skin;

  // 棋盘视觉参数
  static const double _padding = 16.0;

  /// 标准 15x15 星位（天元 + 4 个角星 + 4 个边星）
  static const List<(int, int)> _starPoints = [
    (3, 3), (11, 3), (3, 11), (11, 11),  // 四角星
    (7, 7),                                // 天元
  ];

  @override
  Widget build(BuildContext context) {
    final bc = context.boardColors;
    final shadow = bc.scheme.onSurface.withValues(alpha: 0.15);
    final stoneShadow = bc.scheme.onSurface.withValues(alpha: 0.3);

    return LayoutBuilder(builder: (context, constraints) {
      // 棋盘边长 = min(宽, 高) - padding*2，确保正方形
      final side = constraints.biggest.shortestSide;
      final gridSize = side - _padding * 2;
      // 交点间距：15 条线之间有 14 段
      final step = gridSize / (kGomokuSize - 1);
      final stoneRadius = step * 0.42;

      return SizedBox(
        width: side,
        height: side,
        child: Stack(clipBehavior: Clip.none, children: [
          // 棋盘背景：skin 有 boardBackground → 贴图；否则走 BoardColorStrategy 背景色
          if (skin?.boardBackground != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: skin!.boardBackground!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _boardFallback(bc, shadow),
                ),
              ),
            )
          else
            Positioned.fill(child: _boardFallback(bc, shadow)),
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
          for (int y = 0; y < kGomokuSize; y++)
            for (int x = 0; x < kGomokuSize; x++)
              if (board[y][x] != 0)
                _buildStone(
                  context, x, y, step, stoneRadius,
                  board[y][x] == 1,
                  isLast: lastMove == (x, y),
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
    required Color stoneShadow,
    required Color stoneRim,
  }) {
    final bc = context.boardColors;
    final cx = _padding + x * step;
    final cy = _padding + y * step;
    // 皮肤贴图优先：skin.pieces['black'/'white'] 有图 → Image；否则回退彩色圆
    final skinImage = skin?.pieces[isBlack ? 'black' : 'white'];
    final Widget stoneBody;
    if (skinImage != null) {
      stoneBody = ClipOval(
        child: Image(
          image: skinImage,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _stoneFallback(
            bc, isBlack, radius, stoneShadow, stoneRim, isPreview, isLast),
        ),
      );
    } else {
      stoneBody = _stoneFallback(
          bc, isBlack, radius, stoneShadow, stoneRim, isPreview, isLast);
    }
    return Positioned(
      left: cx - radius,
      top: cy - radius,
      child: Opacity(
        opacity: isPreview ? 0.45 : 1.0,
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 棋子本体（贴图或彩色圆）
              Positioned.fill(child: stoneBody),
              // 阴影（仅非预览）
              if (!isPreview)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: stoneShadow, blurRadius: 2, offset: const Offset(1, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              // 最后一步红点标记（贴图棋子上也叠加，保持与 _stoneFallback 内一致）
              if (isLast && skinImage != null)
                Center(
                  child: Container(
                    width: radius * 0.5,
                    height: radius * 0.5,
                    decoration: BoxDecoration(color: bc.lastMove, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stoneFallback(
    dynamic bc,
    bool isBlack,
    double radius,
    Color stoneShadow,
    Color stoneRim,
    bool isPreview,
    bool isLast,
  ) {
    final color = isBlack ? bc.player1Stone as Color : bc.player2Stone as Color;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
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
                decoration: BoxDecoration(color: bc.lastMove as Color, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }

  Widget _boardFallback(dynamic bc, Color shadow) => Container(
        decoration: BoxDecoration(
          color: bc.background as Color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: shadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
      );

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

    final n = kGomokuSize;
    // 横线
    for (var i = 0; i < n; i++) {
      final y = padding + i * step;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + (n - 1) * step, y),
        paint,
      );
    }
    // 竖线
    for (var i = 0; i < n; i++) {
      final x = padding + i * step;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, padding + (n - 1) * step),
        paint,
      );
    }
    // 星位
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