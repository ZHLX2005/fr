// lib/core/surround_game/widgets/chess_player.dart
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../surround_game_constants.dart';

/// 棋子 Widget —— 自驱位移动画。
///
/// 三处共用：本地热座、Lua 联机、回放页。
///
/// ## 为什么不是 AnimatedPositioned
///
/// 位移本身用 AnimatedPositioned 就够了，但这里还要表达"棋子被拿起来、走过去、
/// 放下"：飞行中途放大 + 阴影散开，落地收回。这需要一条贯穿整段位移的进度量，
/// 所以自己持有 AnimationController。
///
/// ## 三条容易踩的边界，都在这里处理掉了
///
/// 1. **起点存的是格子坐标不是像素**。屏幕尺寸变化时 cellSize 跟着变，像素起点
///    会算错位；存格子坐标则每帧按当前 cellSize 换算，resize 不会把棋子甩出去。
/// 2. **动画途中改目标从当前视觉位置接上**（连走两步、走到一半点取消），
///    不会先瞬移回旧格子再重走。
/// 3. **拖拽时棋子直接跟手**（[dragOffset]），松手后从手指最后的位置滑向落点。
///    以前是"另画一颗浮动棋子跟手 + 真棋子留在原地"，松手瞬间浮动棋子消失、
///    真棋子瞬移到目标，看起来像闪了一下。
class ChessPlayer extends StatefulWidget {
  /// 棋子所在格（cellId = x + y * boardCols）
  final int cellId;
  final double cellSize;
  final Color color;

  /// 拖拽中的手指位置（棋盘局部坐标、以棋子**中心**对齐）。
  /// 非 null → 棋子跟手，不跑动画；变回 null → 从这里滑向 [cellId]。
  final Offset? dragOffset;

  const ChessPlayer({
    super.key,
    required this.cellId,
    required this.cellSize,
    required this.color,
    this.dragOffset,
  });

  @override
  State<ChessPlayer> createState() => _ChessPlayerState();
}

class _ChessPlayerState extends State<ChessPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  /// 位移起点 / 终点，单位是**格**（可以是小数，拖拽松手时就是小数）
  late Offset _fromGrid;
  late Offset _toGrid;

  /// 本段动画的起始"抬升量"：
  /// - 0 → 从棋盘上起步，走一个"抬起-落下"的弧（sin）
  /// - 1 → 从手指上接过来，只需要"落下"（线性衰减）
  double _liftStart = 0;

  @override
  void initState() {
    super.initState();
    _fromGrid = _toGrid = _gridOfCell(widget.cellId);
    _ctrl = AnimationController(
      vsync: this,
      duration: SurroundGameConstants.pieceMoveDuration,
      value: 1, // 初始就位，不要开局先飞一次
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant ChessPlayer old) {
    super.didUpdateWidget(old);

    final drag = widget.dragOffset;
    final wasDrag = old.dragOffset;

    if (drag != null) {
      // 跟手阶段：位置完全由手指决定，停掉动画避免两股力打架
      if (_ctrl.isAnimating) _ctrl.stop();
      return;
    }

    if (wasDrag != null) {
      // 松手：从手指最后的位置滑向落点，并把"举着"的姿态落回棋盘
      _fromGrid = _gridOfPixel(wasDrag, old.cellSize);
      _toGrid = _gridOfCell(widget.cellId);
      _liftStart = 1;
      _ctrl.forward(from: 0);
      return;
    }

    if (widget.cellId != old.cellId) {
      _fromGrid = _currentGrid();
      _toGrid = _gridOfCell(widget.cellId);
      _liftStart = 0;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ═══════════════════════ 坐标换算 ═══════════════════════

  /// 格子编号 → 格坐标
  Offset _gridOfCell(int id) {
    const cols = SurroundGameConstants.boardCols;
    return Offset((id % cols).toDouble(), (id ~/ cols).toDouble());
  }

  /// 手指像素位置（棋子中心）→ 小数格坐标
  ///
  /// 棋子中心 = gx * distance + cellSize / 2（见下方 build 的定位公式），反解即可。
  Offset _gridOfPixel(Offset center, double cellSize) {
    final distance = cellSize * 1.25;
    return Offset(
      (center.dx - cellSize / 2) / distance,
      (center.dy - cellSize / 2) / distance,
    );
  }

  /// 当前这一帧棋子实际在的格坐标
  Offset _currentGrid() => Offset.lerp(_fromGrid, _toGrid, _t.value)!;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final cellSize = widget.cellSize;
        final distance = cellSize * 1.25;
        final pieceSize = cellSize * 0.7;

        final drag = widget.dragOffset;
        // 跟手时抬升拉满；否则按动画进度算
        final double lift;
        final Offset grid;
        if (drag != null) {
          grid = _gridOfPixel(drag, cellSize);
          lift = 1;
        } else {
          grid = _currentGrid();
          lift = _liftStart == 1
              ? (1 - _t.value) // 从手指落回棋盘
              : math.sin(math.pi * _t.value); // 抬起 → 落下
        }

        // Swift ChessPlayer: 棋子中心 = (x*distance + cellSize/2, y*distance + cellSize/2)
        final left = grid.dx * distance + (cellSize - pieceSize) / 2;
        final top = grid.dy * distance + (cellSize - pieceSize) / 2;

        final scale =
            1 + (SurroundGameConstants.pieceLiftScale - 1) * lift;
        final blur = lerpDouble(
          SurroundGameConstants.pieceShadowBlurRest,
          SurroundGameConstants.pieceShadowBlurLift,
          lift,
        )!;
        final shadowDy = lerpDouble(
          SurroundGameConstants.pieceShadowOffsetRest,
          SurroundGameConstants.pieceShadowOffsetLift,
          lift,
        )!;

        return Positioned(
          left: left,
          top: top,
          width: pieceSize,
          height: pieceSize,
          child: IgnorePointer(
            child: Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      // 抬得越高，影子越淡越散
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.4 + 0.1 * lift),
                      blurRadius: blur,
                      offset: Offset(0, shadowDy),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
