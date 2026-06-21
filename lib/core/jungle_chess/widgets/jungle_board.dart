// lib/core/jungle_chess/widgets/jungle_board.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/jungle_constants.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'jungle_piece_widget.dart';
import 'jungle_touch_controller.dart';

class JungleBoard extends StatefulWidget {
  final GameState gameState;
  final JungleTouchController touchController;
  final void Function(Coord from, Coord to) onMoveConfirmed;

  const JungleBoard({
    super.key,
    required this.gameState,
    required this.touchController,
    required this.onMoveConfirmed,
  });

  @override
  State<JungleBoard> createState() => _JungleBoardState();
}

class _JungleBoardState extends State<JungleBoard> {
  @override
  void initState() {
    super.initState();
    widget.touchController.onMoveConfirmed = widget.onMoveConfirmed;
  }

  @override
  void didUpdateWidget(covariant JungleBoard old) {
    super.didUpdateWidget(old);
    widget.touchController.onMoveConfirmed = widget.onMoveConfirmed;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.touchController,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxCellByW = (constraints.maxWidth.isFinite ? constraints.maxWidth : 0) / 7;
            final maxCellByH = (constraints.maxHeight.isFinite ? constraints.maxHeight : 0) / 9;
            final cellSize = (maxCellByW < maxCellByH ? maxCellByW : maxCellByH);
            if (cellSize <= 0) return const SizedBox.shrink();

            final boardW = cellSize * 7;
            final boardH = cellSize * 9;
            widget.touchController.setCellSize(cellSize);

            return Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final hit = _hitTest(details.localPosition, cellSize);
                  if (hit == null) return;
                  widget.touchController
                      .onCellTap(widget.gameState, hit.row * kBoardCols + hit.col);
                },
                onPanStart: (details) {
                  final hit = _hitTest(details.localPosition, cellSize);
                  if (hit == null) return;
                  widget.touchController.onDragStart(
                    widget.gameState,
                    hit.row * kBoardCols + hit.col,
                    details.localPosition,
                  );
                },
                onPanUpdate: (details) {
                  widget.touchController
                      .onDragUpdate(widget.gameState, details.localPosition);
                },
                onPanEnd: (details) {
                  widget.touchController
                      .onDragEnd(widget.gameState, details.localPosition);
                },
                child: SizedBox(
                  width: boardW,
                  height: boardH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 棋盘底色 + 河流 + 网格
                      Positioned.fill(
                        child: CustomPaint(
                          size: Size(boardW, boardH),
                          painter: _BoardBgPainter(cellSize: cellSize),
                        ),
                      ),
                      // 陷阱 SVG 图标（覆盖在陷阱格上）
                      ..._buildTrapIcons(cellSize),
                      // 兽穴 SVG 图标（覆盖在兽穴格上）
                      ..._buildDenIcons(cellSize),
                      // 合法目标标记
                      ...widget.touchController.validTargets.map((coord) {
                        final idx = coord.index;
                        final hasPiece = widget.gameState.pieces.containsKey(idx) &&
                            widget.gameState.pieces[idx]!.isAlive;
                        final isHover = widget.touchController.dragHoverIndex == idx &&
                            widget.touchController.phase == TouchPhase.dragging;
                        return Positioned(
                          left: coord.col * cellSize + cellSize / 2 - 12,
                          top: coord.row * cellSize + cellSize / 2 - 12,
                          width: 24,
                          height: 24,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasPiece
                                    ? Colors.red.withValues(alpha: isHover ? 0.9 : 0.55)
                                    : Colors.green.withValues(alpha: isHover ? 0.9 : 0.55),
                                border: isHover
                                    ? Border.all(color: Colors.amber, width: 2.5)
                                    : null,
                                boxShadow: isHover
                                    ? [
                                        BoxShadow(
                                          color: Colors.amber.withValues(alpha: 0.6),
                                          blurRadius: 8,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        );
                      }),
                      // 棋子层（全部 IgnorePointer）
                      ...widget.gameState.pieces.values.where((p) => p.isAlive).map((piece) {
                        final isDragging = widget.touchController.phase ==
                                TouchPhase.dragging &&
                            widget.touchController.selectedIndex == piece.position.index;
                        if (isDragging) return const SizedBox.shrink();
                        final isSelected =
                            widget.touchController.selectedIndex == piece.position.index;
                        return Positioned(
                          left: piece.position.col * cellSize +
                              (cellSize - cellSize * kPieceRatio) / 2,
                          top: piece.position.row * cellSize +
                              (cellSize - cellSize * kPieceRatio) / 2,
                          width: cellSize * kPieceRatio,
                          height: cellSize * kPieceRatio,
                          child: IgnorePointer(
                            child: JunglePieceWidget(
                              piece: piece,
                              isSelected: isSelected,
                              size: cellSize,
                            ),
                          ),
                        );
                      }),
                      // 拖动中跟随手指的棋子（用实时 Offset 渲染 → 丝滑）
                      if (widget.touchController.phase == TouchPhase.dragging &&
                          widget.touchController.selectedIndex != null)
                        _buildDraggingPiece(cellSize: cellSize, boardW: boardW, boardH: boardH),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 把所有陷阱坐标渲染为 SvgPicture.asset
  List<Widget> _buildTrapIcons(double cellSize) {
    final traps = <int>[...kBlueTraps, ...kRedTraps];
    return traps.map((idx) {
      final row = idx ~/ 7;
      final col = idx % 7;
      final iconSize = cellSize * 0.55;
      return Positioned(
        left: col * cellSize + (cellSize - iconSize) / 2,
        top: row * cellSize + (cellSize - iconSize) / 2,
        width: iconSize,
        height: iconSize,
        child: IgnorePointer(
          child: SvgPicture.asset(
            'assets/animal/trap.svg',
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(Color(0xFF9CA3AF), BlendMode.srcIn),
          ),
        ),
      );
    }).toList();
  }

  /// 把蓝穴 / 红穴渲染为 SvgPicture.asset
  List<Widget> _buildDenIcons(double cellSize) {
    final dens = [
      (idx: kBlueDen, color: const Color(0xFF3B82F6)),
      (idx: kRedDen, color: const Color(0xFFEF4444)),
    ];
    return dens.map((d) {
      final row = d.idx ~/ 7;
      final col = d.idx % 7;
      final iconSize = cellSize * 0.7;
      return Positioned(
        left: col * cellSize + (cellSize - iconSize) / 2,
        top: row * cellSize + (cellSize - iconSize) / 2,
        width: iconSize,
        height: iconSize,
        child: IgnorePointer(
          child: SvgPicture.asset(
            'assets/animal/den.svg',
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(d.color, BlendMode.srcIn),
          ),
        ),
      );
    }).toList();
  }

  /// 拖动中的棋子：圆心钉在手指位置 → 真正"丝滑"
  Widget _buildDraggingPiece({
    required double cellSize,
    required double boardW,
    required double boardH,
  }) {
    final ctrl = widget.touchController;
    final fromIdx = ctrl.selectedIndex!;
    final piece = widget.gameState.pieces[fromIdx];
    if (piece == null) return const SizedBox.shrink();
    final finger = ctrl.dragFingerPos;
    if (finger == null) return const SizedBox.shrink();

    final pieceSize = cellSize * kPieceRatio;
    // 圆心 = 手指 → 左上 = 手指 - 半径
    double left = finger.dx - pieceSize / 2;
    double top = finger.dy - pieceSize / 2;
    // 限制在棋盘内（避免拖出棋盘仍渲染）
    left = left.clamp(0.0, boardW - pieceSize);
    top = top.clamp(0.0, boardH - pieceSize);

    return Positioned(
      left: left,
      top: top,
      width: pieceSize,
      height: pieceSize,
      child: IgnorePointer(
        // 轻微缩放 + 抬升阴影（更"浮起"感）
        child: Transform.scale(
          scale: 1.1,
          child: JunglePieceWidget(
            piece: piece,
            isSelected: true,
            size: cellSize,
            elevated: true,
          ),
        ),
      ),
    );
  }

  _BoardHit? _hitTest(Offset localPos, double cellSize) {
    if (localPos.dx < 0 || localPos.dy < 0 ||
        localPos.dx >= cellSize * 7 || localPos.dy >= cellSize * 9) {
      return null;
    }
    final col = (localPos.dx / cellSize).floor().clamp(0, kBoardCols - 1);
    final row = (localPos.dy / cellSize).floor().clamp(0, kBoardRows - 1);
    return _BoardHit(row: row, col: col);
  }
}

class _BoardHit {
  final int row;
  final int col;
  const _BoardHit({required this.row, required this.col});
}

class _BoardBgPainter extends CustomPainter {
  final double cellSize;
  _BoardBgPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = kBoardBg;
    canvas.drawRect(Rect.fromLTWH(0, 0, cellSize * 7, cellSize * 9), bgPaint);

    // 河流
    final riverPaint = Paint()..color = kRiverColor;
    for (final idx in kRiverCells) {
      final row = idx ~/ 7;
      final col = idx % 7;
      canvas.drawRect(
        Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
        riverPaint,
      );
    }

    // 网格线
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.brown.withValues(alpha: 0.25);
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 7; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
          gridPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}