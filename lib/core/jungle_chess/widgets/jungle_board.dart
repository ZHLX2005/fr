// lib/core/jungle_chess/widgets/jungle_board.dart
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/jungle_constants.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'jungle_piece_widget.dart';
import 'jungle_touch_controller.dart';

/// 斗兽棋棋盘。
///
/// 两种模式共用同一套渲染，保证教程演示与正式对局视觉完全一致：
/// - **可交互**：传入 [touchController] + [onMoveConfirmed]，挂手势层。
/// - **只读演示**：[touchController] 为 null，不挂手势，仅按 [gameState] 绘制。
///   教程通过 [highlightCells] 点亮河流 / 陷阱 / 兽穴等要讲解的格子。
///
/// 棋子层用 [AnimatedPositioned] + 稳定 key（颜色_动物），走子是平滑位移而非瞬移。
class JungleBoard extends StatefulWidget {
  final GameState gameState;
  final JungleTouchController? touchController;
  final void Function(Coord from, Coord to)? onMoveConfirmed;

  /// 格子高亮：1D index → 覆盖色（半透明）。教程讲解用，正式对局传空。
  final Map<int, Color> highlightCells;

  const JungleBoard({
    super.key,
    required this.gameState,
    this.touchController,
    this.onMoveConfirmed,
    this.highlightCells = const {},
  });

  /// 是否处于可交互模式
  bool get interactive => touchController != null;

  @override
  State<JungleBoard> createState() => _JungleBoardState();
}

class _JungleBoardState extends State<JungleBoard> {
  @override
  void initState() {
    super.initState();
    _bindCallback();
  }

  @override
  void didUpdateWidget(covariant JungleBoard old) {
    super.didUpdateWidget(old);
    _bindCallback();
  }

  void _bindCallback() {
    final cb = widget.onMoveConfirmed;
    if (cb != null) widget.touchController?.onMoveConfirmed = cb;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.touchController;
    if (ctrl == null) return _buildLayout(null);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) => _buildLayout(ctrl),
    );
  }

  Widget _buildLayout(JungleTouchController? ctrl) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCellByW =
            (constraints.maxWidth.isFinite ? constraints.maxWidth : 0) / 7;
        final maxCellByH =
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 0) / 9;
        final cellSize = (maxCellByW < maxCellByH ? maxCellByW : maxCellByH);
        if (cellSize <= 0) return const SizedBox.shrink();

        final boardW = cellSize * 7;
        final boardH = cellSize * 9;
        ctrl?.setCellSize(cellSize);

        final board = SizedBox(
          width: boardW,
          height: boardH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 棋盘底色 + 河流 + 网格 + 教程高亮
              Positioned.fill(
                child: CustomPaint(
                  size: Size(boardW, boardH),
                  painter: _BoardBgPainter(
                    cellSize: cellSize,
                    highlights: widget.highlightCells,
                  ),
                ),
              ),
              // 陷阱 SVG 图标（覆盖在陷阱格上）
              ..._buildTrapIcons(cellSize),
              // 兽穴 SVG 图标（覆盖在兽穴格上）
              ..._buildDenIcons(cellSize),
              // 合法目标标记（仅交互模式）
              if (ctrl != null) ..._buildTargetMarkers(ctrl, cellSize),
              // 棋子层
              ..._buildPieces(ctrl, cellSize),
              // 拖动中跟随手指的棋子（用实时 Offset 渲染 → 丝滑）
              if (ctrl != null &&
                  ctrl.phase == TouchPhase.dragging &&
                  ctrl.selectedIndex != null)
                _buildDraggingPiece(
                  ctrl: ctrl,
                  cellSize: cellSize,
                  boardW: boardW,
                  boardH: boardH,
                ),
            ],
          ),
        );

        if (ctrl == null) return Center(child: board);

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final hit = _hitTest(details.localPosition, cellSize);
              if (hit == null) return;
              ctrl.onCellTap(
                  widget.gameState, hit.row * kBoardCols + hit.col);
            },
            onPanStart: (details) {
              final hit = _hitTest(details.localPosition, cellSize);
              if (hit == null) return;
              ctrl.onDragStart(
                widget.gameState,
                hit.row * kBoardCols + hit.col,
                details.localPosition,
              );
            },
            onPanUpdate: (details) {
              ctrl.onDragUpdate(widget.gameState, details.localPosition);
            },
            onPanEnd: (details) {
              ctrl.onDragEnd(widget.gameState, details.localPosition);
            },
            child: board,
          ),
        );
      },
    );
  }

  /// 合法落点圆点：空格绿色 / 可吃子红色，手指悬停时放大高亮
  List<Widget> _buildTargetMarkers(
      JungleTouchController ctrl, double cellSize) {
    return ctrl.validTargets.map((coord) {
      final idx = coord.index;
      final hasPiece = widget.gameState.pieces.containsKey(idx) &&
          widget.gameState.pieces[idx]!.isAlive;
      final isHover =
          ctrl.dragHoverIndex == idx && ctrl.phase == TouchPhase.dragging;
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
              border:
                  isHover ? Border.all(color: Colors.amber, width: 2.5) : null,
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
    }).toList();
  }

  /// 棋子层。key 用「颜色_动物」而非格子下标，棋子换格时 Flutter 才能把新旧
  /// widget 认成同一个，[AnimatedPositioned] 才会插值出位移动画。
  List<Widget> _buildPieces(JungleTouchController? ctrl, double cellSize) {
    final pieceSize = cellSize * kPieceRatio;
    final inset = (cellSize - pieceSize) / 2;

    return widget.gameState.pieces.values.where((p) => p.isAlive).map((piece) {
      final isDragging = ctrl != null &&
          ctrl.phase == TouchPhase.dragging &&
          ctrl.selectedIndex == piece.position.index;
      final isSelected = ctrl?.selectedIndex == piece.position.index;

      return AnimatedPositioned(
        key: ValueKey('${piece.color.name}_${piece.animal.name}'),
        duration: kPieceMoveDuration,
        curve: Curves.easeOutCubic,
        left: piece.position.col * cellSize + inset,
        top: piece.position.row * cellSize + inset,
        width: pieceSize,
        height: pieceSize,
        child: IgnorePointer(
          // 拖动中的棋子由 _buildDraggingPiece 单独跟手渲染，这里留空位
          child: Opacity(
            opacity: isDragging ? 0 : 1,
            child: JunglePieceWidget(
              piece: piece,
              isSelected: isSelected,
              size: cellSize,
              flipped: piece.color == PlayerColor.red,
            ),
          ),
        ),
      );
    }).toList();
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
            colorFilter:
                const ColorFilter.mode(Color(0xFF9CA3AF), BlendMode.srcIn),
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
    required JungleTouchController ctrl,
    required double cellSize,
    required double boardW,
    required double boardH,
  }) {
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
            flipped: piece.color == PlayerColor.red,
          ),
        ),
      ),
    );
  }

  _BoardHit? _hitTest(Offset localPos, double cellSize) {
    if (localPos.dx < 0 ||
        localPos.dy < 0 ||
        localPos.dx >= cellSize * 7 ||
        localPos.dy >= cellSize * 9) {
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
  final Map<int, Color> highlights;

  _BoardBgPainter({required this.cellSize, this.highlights = const {}});

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

    // 教程高亮（叠在底色之上、网格之下）
    highlights.forEach((idx, color) {
      final row = idx ~/ 7;
      final col = idx % 7;
      canvas.drawRect(
        Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
        Paint()..color = color,
      );
    });

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
  bool shouldRepaint(covariant _BoardBgPainter old) =>
      old.cellSize != cellSize || !mapEquals(old.highlights, highlights);
}
