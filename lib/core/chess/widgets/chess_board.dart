// lib/core/chess/widgets/chess_board.dart
//
// 8x8 棋盘的纯渲染层（Stateless）。
//
// 责任：
//   · 8x8 两色格 + 坐标标签（a-h / 1-8，可翻转）+ 选中/上一步/合法走法/吃子高亮
//   · 把每个非空格子的 [BoardState.cells] 通过 [ChessSkin] 找 [ImageProvider]
//     渲染 [ChessPiece]
//   · tap 通过 [onSquareTap] 透传（1D index）
//   · 拖动（board-gesture-patterns）：传入 [onDragSquareStart]/[onDragSquareEnd]
//     后挂顶层手势层 —— tap + pan 收敛到单一 GestureDetector，pan 坐标
//     （翻转感知）转成 1D index 回调；浮起棋子由 [draggingSquare]/
//     [dragFingerPos] 参数驱动，跟手渲染。
//
// 不负责：
//   · 走法生成（[ChessEngine]）
//   · 选中态管理（[ChessController] / 对弈页拥有）
//   · 升变面板（v2）
//
// 颜色走 [context.chessColors]（v6.2.1 第 6 strategy 通道）：
//   · lightSquare / darkSquare      → 两色格
//   · selectedSquare                → 选中格
//   · lastMoveHighlight             → 上一步 from/to
//   · legalMoveHint                 → 空格走法圆点
//   · captureHint                   → 吃子走法圆圈
//   · coordinateLabel               → a-h / 1-8 字符
//   · gridLine                      → 格子描边（可选，浅色）
//
// 自定义棋盘配色（[boardPalette]，可空）：
//   非空时按"用户自定义 > 主题默认"逐角色覆盖 —— 即
//     boardPalette?.X ?? context.chessColors.X
//   未覆盖的角色（palette 对应字段为 null）仍走主题默认。
//   [boardPalette] == null → 行为与旧版完全一致（全部跟随主题）。
//
// 翻转：
//   · [flipped] == false → 白方在底，a1-h1 在底部（标准白方视角）
//   · [flipped] == true  → 棋盘上下翻转，a8-h8 在底（黑方视角）
//   · [flipped] 默认 false（白方视角，整局稳定）。
//     渲染**不依赖** [sideToMove] —— 曾默认 `sideToMove == black`，导致本地
//     对弈每走一步棋盘 180° 翻转、"走子后棋盘变样"。联机对局应显式传入
//     "角色稳定"的 flipped（如 _myColor == black），让视角整局稳定。
//
// 棋子图像优先用 [ChessSkin.boardBackground] 拼棋盘底图（透明 PNG 1:1），
// 若为 null 则走默认两色格。

import 'package:flutter/widgets.dart';

import '../../../widgets/context_chess_colors.dart';
import '../constants/chess_constants.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../skins/chess_skin.dart';
import 'board_palette.dart';
import 'chess_piece.dart';

import '../../../core/theme/colors/strategy/chess_color_strategy/chess_color_strategy.dart'
    show ChessColorStrategy;
import 'package:flutter/material.dart' show ColorScheme;

/// 8x8 棋盘 + 坐标 + 高亮 + 棋子渲染。
///
/// 所有交互通过 [onSquareTap] 1D index 透传给上层控制器。
class ChessBoard extends StatelessWidget {
  /// 当前棋盘局面（含 64 cells）。
  final BoardState state;

  /// 当前使用的皮肤（影响棋盘底图 + 棋子图像）。
  final ChessSkin skin;

  /// 哪一方在底部。
  /// - white → a1-h1 在底，标准白方视角
  /// - black → 棋盘上下翻转，a8-h8 在底
  ///
  /// 仅作语义标注 / 调用方便捷字段，**渲染不使用**（防"走子后棋盘变样"）。
  final PieceColor sideToMove;

  /// 是否翻转棋盘（黑方视角）。
  /// 默认 false（白方视角，整局稳定）；联机对局由"角色"（我方颜色）驱动
  /// 并整局稳定。渲染不依赖 [sideToMove]。
  final bool? flipped;

  /// 当前选中的 1D index（高亮最强）。
  final int? selectedSquare;

  /// 合法走法目标（1D index）—— 用作走法提示圆点 / 吃子圆圈。
  final Set<int> legalTargets;

  /// 上一步走法 —— from / to 用 lastMoveHighlight 着色。
  final Move? lastMove;

  /// 点击回调（1D index）。
  final void Function(int square)? onSquareTap;

  /// 拖动开始：手指按在某格并开始拖动（square + 手指在 8x8 网格局部坐标）。
  ///
  /// 非 null 时棋盘挂顶层手势层（tap + pan 收敛单一 GestureDetector），
  /// tap 仍走 [onSquareTap]（选中-点击两段式保持不变）。
  /// 合法性 / 回合门由调用方判定（棋盘只做翻转感知的坐标映射）。
  final void Function(int square, Offset fingerPos)? onDragSquareStart;

  /// 拖动移动：手指位置变化（square = 当前命中格；null = 拖出 8x8 网格）。
  final void Function(int? square, Offset fingerPos)? onDragSquareUpdate;

  /// 拖动结束（手指抬起 / 系统取消）：square = 松手命中格（null = 网格外）。
  /// 松手在合法目标 → 调用方提交走法；非法 → 调用方弹回（保持选中）。
  final void Function(int? square, Offset fingerPos)? onDragSquareEnd;

  /// 正在拖动的格子（1D index）：该格棋子隐藏、浮起棋子按 [dragFingerPos]
  /// 跟手渲染。null = 无拖动。
  final int? draggingSquare;

  /// 手指在 8x8 网格局部坐标系的实时位置（[onDragSquareStart/Update]
  /// 回传给本参数）。null = 无拖动。
  final Offset? dragFingerPos;

  /// 拖动悬停格（1D index）：合法目标在悬停时放大高亮。null = 无。
  final int? dragHoverSquare;

  /// 自定义棋盘配色（可空）。null = 完全跟随主题（旧行为）。
  ///
  /// 优先级：`boardPalette?.X ?? context.chessColors.X`
  /// （用户自定义 > 主题默认 —— 自定义颜色永远优先，未覆盖的角色跟随主题）。
  final BoardPalette? boardPalette;

  const ChessBoard({
    super.key,
    required this.state,
    required this.skin,
    required this.sideToMove,
    this.flipped,
    this.selectedSquare,
    this.legalTargets = const <int>{},
    this.lastMove,
    this.onSquareTap,
    this.onDragSquareStart,
    this.onDragSquareUpdate,
    this.onDragSquareEnd,
    this.draggingSquare,
    this.dragFingerPos,
    this.dragHoverSquare,
    this.boardPalette,
  });

  /// 解析当前棋盘配色 —— 用户自定义优先，未覆盖角色回退主题默认。
  ///
  /// 核心语义：`palette?.X ?? theme.X`（用户自定义 > 主题）。
  /// [boardPalette] 为 null 或空 → 全部走主题。
  ChessColorStrategy _resolveColors(BuildContext context) {
    final theme = context.chessColors;
    final p = boardPalette;
    if (p == null || p.isEmpty) return theme;
    return _ResolvedChessColors(
      lightSquare: p.lightSquare ?? theme.lightSquare,
      darkSquare: p.darkSquare ?? theme.darkSquare,
      gridLine: p.gridLine ?? theme.gridLine,
      coordinateLabel: theme.coordinateLabel,
      selectedSquare: p.selectedSquare ?? theme.selectedSquare,
      lastMoveHighlight: p.lastMoveHighlight ?? theme.lastMoveHighlight,
      legalMoveHint: p.legalMoveHint ?? theme.legalMoveHint,
      captureHint: p.captureHint ?? theme.captureHint,
      checkWarning: p.checkWarning ?? theme.checkWarning,
      checkmateOverlay: theme.checkmateOverlay,
      promotionOverlay: theme.promotionOverlay,
      promotionBorder: theme.promotionBorder,
      scheme: theme.scheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _resolveColors(context);
    // 视角默认白方（整局稳定）——渲染不依赖 sideToMove（防每步翻转）。
    final flipped = this.flipped ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        if (side <= 0) return const SizedBox.shrink();
        // 留 16px 给坐标标签
        final labelSpace = side < 280 ? 12.0 : 16.0;
        final boardSize = side - labelSpace * 2;
        if (boardSize <= 0) return const SizedBox.shrink();
        final cell = boardSize / kBoardCols;

        return Center(
          child: SizedBox(
            width: boardSize + labelSpace * 2,
            height: boardSize + labelSpace * 2,
            child: Stack(
              children: [
                // 坐标标签（左 / 下）
                Positioned(
                  left: 0,
                  top: labelSpace,
                  width: labelSpace,
                  height: boardSize,
                  child: _RankLabels(
                    flipped: flipped,
                    labelColor: colors.coordinateLabel,
                    cellSize: cell,
                  ),
                ),
                Positioned(
                  left: labelSpace,
                  top: labelSpace + boardSize,
                  width: boardSize,
                  height: labelSpace,
                  child: _FileLabels(
                    flipped: flipped,
                    labelColor: colors.coordinateLabel,
                    cellSize: cell,
                  ),
                ),
                // 棋盘
                Positioned(
                  left: labelSpace,
                  top: labelSpace,
                  width: boardSize,
                  height: boardSize,
                  child: _BoardGrid(
                    state: state,
                    skin: skin,
                    flipped: flipped,
                    cellSize: cell,
                    colors: colors,
                    selectedSquare: selectedSquare,
                    legalTargets: legalTargets,
                    lastMove: lastMove,
                    onSquareTap: onSquareTap,
                    onDragSquareStart: onDragSquareStart,
                    onDragSquareUpdate: onDragSquareUpdate,
                    onDragSquareEnd: onDragSquareEnd,
                    draggingSquare: draggingSquare,
                    dragFingerPos: dragFingerPos,
                    dragHoverSquare: dragHoverSquare,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 8x8 棋盘网格（两色格 + 高亮 + 棋子）
class _BoardGrid extends StatelessWidget {
  final BoardState state;
  final ChessSkin skin;
  final bool flipped;
  final double cellSize;

  /// 已解析的棋盘配色（用户自定义优先 + 主题兜底），由父级 ChessBoard 传入。
  final ChessColorStrategy colors;

  final int? selectedSquare;
  final Set<int> legalTargets;
  final Move? lastMove;
  final void Function(int square)? onSquareTap;

  /// 拖动回调（Start + End 同时非 null 时挂顶层手势层 [_BoardDragLayer]）。
  final void Function(int square, Offset fingerPos)? onDragSquareStart;
  final void Function(int? square, Offset fingerPos)? onDragSquareUpdate;
  final void Function(int? square, Offset fingerPos)? onDragSquareEnd;

  /// 拖动渲染状态（调用方把回调收到的值回传进来）。
  final int? draggingSquare;
  final Offset? dragFingerPos;
  final int? dragHoverSquare;

  const _BoardGrid({
    required this.state,
    required this.skin,
    required this.flipped,
    required this.cellSize,
    required this.colors,
    this.selectedSquare,
    this.legalTargets = const <int>{},
    this.lastMove,
    this.onSquareTap,
    this.onDragSquareStart,
    this.onDragSquareUpdate,
    this.onDragSquareEnd,
    this.draggingSquare,
    this.dragFingerPos,
    this.dragHoverSquare,
  });

  /// 1D index (白方视角) → 屏幕 (col, row)。
  /// flipped 时 row 反转。
  (int, int) _displayOf(int idx) {
    final row = idx ~/ kBoardCols;
    final col = idx % kBoardCols;
    if (flipped) {
      return (kBoardCols - 1 - col, kBoardRows - 1 - row);
    }
    return (col, row);
  }

  @override
  Widget build(BuildContext context) {
    // 走子方颜色从"选中格的棋子"派生（而非 state.sideToMove）——
    // 渲染不依赖轮次：合法目标标记的"吃子圈 vs 空格点"在走子前后表现一致。
    final moverColor = selectedSquare != null
        ? state.pieceColorAt(selectedSquare!)
        : null;
    final board = SizedBox(
      width: cellSize * kBoardCols,
      height: cellSize * kBoardRows,
      child: Stack(
        children: [
          // 棋盘底图（如果皮肤提供）
          if (skin.boardBackground != null)
            Positioned.fill(
              child: Image(
                image: skin.boardBackground!,
                fit: BoxFit.cover,
                // Fix C：底图加载失败（离线 / 404）→ 不渲染，让上层两色格透出，
                // 绝不留永不完成的 loading 占位。
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          // 两色格（Positioned.fill 覆盖；boardBackground 在下层）
          for (var idx = 0; idx < kBoardSquares; idx++)
            () {
              final (col, row) = _displayOf(idx);
              final isLight = (row + col).isEven;
              final highlight = _squareHighlight(
                idx,
                selectedSquare,
                lastMove,
                colors,
              );
              return Positioned(
                left: col * cellSize,
                top: row * cellSize,
                width: cellSize,
                height: cellSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: onSquareTap == null
                      ? null
                      : (_) => onSquareTap!(idx),
                  child: Container(
                    decoration: BoxDecoration(
                      color: highlight ??
                          (isLight ? colors.lightSquare : colors.darkSquare),
                      border: Border.all(
                        color: colors.gridLine.withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                    ),
                    // 走法提示（圆点 / 圆圈）—— 颜色走已解析配色（用户自定义优先）
                    child: _LegalMarker(
                      isLegalTarget: legalTargets.contains(idx),
                      hasOpponent: _isOpponentOn(idx, moverColor),
                      emptySquare: state.isEmpty(idx),
                      cellSize: cellSize,
                      legalMoveHint: colors.legalMoveHint,
                      captureHint: colors.captureHint,
                      isDragHover:
                          draggingSquare != null && dragHoverSquare == idx,
                    ),
                  ),
                ),
              );
            }(),
          // 棋子层 —— IgnorePointer 让棋子不抢走下层格子的 tap；
          // 拖动中的棋子由浮起层跟手渲染，原格留空位（Opacity 0）
          for (var idx = 0; idx < kBoardSquares; idx++)
            if (!state.isEmpty(idx))
              () {
                final (col, row) = _displayOf(idx);
                final slot = state.slotAt(idx)!;
                final type = PieceSlot.unpackType(slot);
                final pieceColor = PieceSlot.unpackColorEnum(slot);
                final key = chessSkinKeyOf(pieceColor, type);
                final image = skin.pieces[key];
                // 拖动中的原格棋子隐藏（浮起层接管渲染）
                final hidden = draggingSquare == idx;
                if (image == null) {
                  // fallback：unicode 字符
                  return Positioned(
                    left: col * cellSize,
                    top: row * cellSize,
                    width: cellSize,
                    height: cellSize,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: hidden ? 0 : 1,
                        child: Center(
                          child: Text(
                            _unicodeFallback(key),
                            style: TextStyle(fontSize: cellSize * 0.7),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final pad = cellSize * 0.05;
                return Positioned(
                  left: col * cellSize + pad,
                  top: row * cellSize + pad,
                  width: cellSize - pad * 2,
                  height: cellSize - pad * 2,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: hidden ? 0 : 1,
                      // 稳定 key（白方视角 1D index）：拖动换格时 Flutter 认出
                      // 同一棋子，测试也可按 key 精确定位棋子。
                      child: ChessPiece(
                        key: ValueKey<String>('piece_$idx'),
                        image: image,
                        size: cellSize - pad * 2,
                        pieceKey: key,
                      ),
                    ),
                  ),
                );
              }(),
          // 拖动浮起棋子：中心钉在手指位置（clamp 棋盘内），放大 1.15"浮起"。
          // 放在手势层**之后**（Stack 末尾）：松手层/拖动层之前的子项索引稳定，
          // 拖动开始 setState 插入本子项时不会让手势层元素被按索引回收。
          if (draggingSquare != null && dragFingerPos != null)
            _buildDraggingPiece(draggingSquare!, dragFingerPos!),
          // 顶层手势层（挂载条件 = 拖动回调存在）：tap 透传 + pan 拖动，
          // opaque 覆盖在格子/棋子之上，避免双 GestureDetector 双触发。
          // 必须带稳定 key —— 拖动中浮起棋子是动态子项，无 key 时 Stack 按索引
          // 匹配会把手势层元素回收（拖动中断、pan 被 abort）。
          if (onDragSquareStart != null && onDragSquareEnd != null)
            Positioned.fill(
              key: const ValueKey<String>('chess_board_drag_layer'),
              child: _BoardDragLayer(
                cellSize: cellSize,
                flipped: flipped,
                onSquareTap: onSquareTap,
                onDragStart: onDragSquareStart!,
                onDragUpdate: onDragSquareUpdate,
                onDragEnd: onDragSquareEnd!,
              ),
            ),
        ],
      ),
    );
    return board;
  }

  /// 拖动中的棋子：圆心钉在手指位置 → 跟手"丝滑"（jungle _buildDraggingPiece 同款）。
  Widget _buildDraggingPiece(int fromIdx, Offset finger) {
    final slot = state.slotAt(fromIdx);
    if (slot == null) return const SizedBox.shrink();
    final type = PieceSlot.unpackType(slot);
    final pieceColor = PieceSlot.unpackColorEnum(slot);
    final key = chessSkinKeyOf(pieceColor, type);
    final image = skin.pieces[key];
    final boardW = cellSize * kBoardCols;
    final boardH = cellSize * kBoardRows;
    // 圆心 = 手指 → 左上 = 手指 - 半格；clamp 在棋盘内
    final left = (finger.dx - cellSize / 2).clamp(0.0, boardW - cellSize);
    final top = (finger.dy - cellSize / 2).clamp(0.0, boardH - cellSize);
    return Positioned(
      left: left,
      top: top,
      width: cellSize,
      height: cellSize,
      child: IgnorePointer(
        child: Transform.scale(
          scale: 1.15,
          child: image != null
              ? ChessPiece(image: image, size: cellSize, pieceKey: key)
              : Center(
                  child: Text(
                    _unicodeFallback(key),
                    style: TextStyle(fontSize: cellSize * 0.7),
                  ),
                ),
        ),
      ),
    );
  }

  /// 计算 idx 格的背景色覆盖（null = 不覆盖，走默认两色格）
  Color? _squareHighlight(
    int idx,
    int? selected,
    Move? lastMove,
    ChessColorStrategy colors,
  ) {
    if (selected != null && idx == selected) {
      return colors.selectedSquare;
    }
    if (lastMove != null && (idx == lastMove.from || idx == lastMove.to)) {
      return colors.lastMoveHighlight;
    }
    return null;
  }

  /// idx 格上是否是"被吃方"棋子（相对走子方 [moverColor]，从选中格棋子派生）。
  ///
  /// 渲染不依赖 state.sideToMove：走子轮次切换不改变任何格子外观。
  bool _isOpponentOn(int idx, PieceColor? moverColor) {
    final c = state.pieceColorAt(idx);
    if (c == null || moverColor == null) return false;
    return c != moverColor;
  }
}

/// 已解析的棋盘配色 —— 用户自定义（BoardPalette）逐角色覆盖主题后的结果。
///
/// 由 [ChessBoard._colors] 构造：`palette?.X ?? theme.X`（用户自定义 > 主题）。
/// 未被 BoardPalette 覆盖的角色（coordinateLabel / checkmateOverlay /
/// promotionOverlay / promotionBorder，BoardPalette v1 不含这些字段）
/// 直接透传主题值。
class _ResolvedChessColors extends ChessColorStrategy {
  @override
  final Color lightSquare;
  @override
  final Color darkSquare;
  @override
  final Color gridLine;
  @override
  final Color coordinateLabel;
  @override
  final Color selectedSquare;
  @override
  final Color lastMoveHighlight;
  @override
  final Color legalMoveHint;
  @override
  final Color captureHint;
  @override
  final Color checkWarning;
  @override
  final Color checkmateOverlay;
  @override
  final Color promotionOverlay;
  @override
  final Color promotionBorder;

  /// 主题兜底 scheme（透传 context.chessColors.scheme，本 widget 不直接读）。
  final ColorScheme _scheme;

  const _ResolvedChessColors({
    required this.lightSquare,
    required this.darkSquare,
    required this.gridLine,
    required this.coordinateLabel,
    required this.selectedSquare,
    required this.lastMoveHighlight,
    required this.legalMoveHint,
    required this.captureHint,
    required this.checkWarning,
    required this.checkmateOverlay,
    required this.promotionOverlay,
    required this.promotionBorder,
    required ColorScheme scheme,
  }) : _scheme = scheme;

  @override
  ColorScheme get scheme => _scheme;

  // ==/hashCode 继承自 ChessColorStrategy 基类（按 12 角色逐字段比较）。
}

/// 走法提示小点 / 圆圈
class _LegalMarker extends StatelessWidget {
  final bool isLegalTarget;
  final bool hasOpponent;
  final bool emptySquare;
  final double cellSize;

  /// 已解析的配色（用户自定义优先，由 _BoardGrid 传入）。
  final Color legalMoveHint;
  final Color captureHint;

  /// 拖动悬停在本格：标记放大 + 描边（拖动中的目标点预览）。
  final bool isDragHover;

  const _LegalMarker({
    required this.isLegalTarget,
    required this.hasOpponent,
    required this.emptySquare,
    required this.cellSize,
    required this.legalMoveHint,
    required this.captureHint,
    this.isDragHover = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLegalTarget) return const SizedBox.shrink();
    // 吃子走法 → 圆圈；空格走法 → 圆点；拖动悬停 → 放大强调
    if (hasOpponent) {
      final sizeFactor = isDragHover ? 0.95 : 0.85;
      return Center(
        child: Container(
          width: cellSize * sizeFactor,
          height: cellSize * sizeFactor,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: captureHint,
              width: cellSize * 0.08,
            ),
          ),
        ),
      );
    }
    if (emptySquare) {
      final sizeFactor = isDragHover ? 0.46 : 0.32;
      return Center(
        child: Container(
          width: cellSize * sizeFactor,
          height: cellSize * sizeFactor,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: legalMoveHint,
            border: isDragHover
                ? Border.all(color: captureHint, width: cellSize * 0.05)
                : null,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 棋盘顶层手势层 —— 单 GestureDetector 收敛 tap + pan（board-gesture-patterns §3.1）。
///
/// 挂在 8x8 网格 Stack 最顶（opaque）：拖动回调存在时由本层接管全部手势 ——
/// tap 仍透传 [onSquareTap]（选中-点击两段式不变），pan 坐标（翻转感知）
/// 映射成 1D index 走拖动回调。不做合法性/回合判定（调用方职责）。
///
/// 单 GestureDetector 防双触发；[StatefulWidget] 记录最近 pan 位置
/// （DragEndDetails 无 localPosition，用最后的 update 位置代替）。
class _BoardDragLayer extends StatefulWidget {
  const _BoardDragLayer({
    required this.cellSize,
    required this.flipped,
    this.onSquareTap,
    required this.onDragStart,
    this.onDragUpdate,
    required this.onDragEnd,
  });

  final double cellSize;
  final bool flipped;
  final void Function(int square)? onSquareTap;
  final void Function(int square, Offset fingerPos) onDragStart;
  final void Function(int? square, Offset fingerPos)? onDragUpdate;
  final void Function(int? square, Offset fingerPos) onDragEnd;

  @override
  State<_BoardDragLayer> createState() => _BoardDragLayerState();
}

class _BoardDragLayerState extends State<_BoardDragLayer> {
  /// 最近一次 pan 手指位置（网格局部坐标）；pan end/cancel 用它结算落点。
  Offset? _lastLocal;

  /// 按下（pan down）时记住的格子 —— pan 识别后 onPanStart 的 localPosition
  /// 是"已偏移后的当前位置"，不是按下的格子；onPanDown 在按下瞬间触发、
  /// 坐标准确，保证拖动起点 = 手指按下的那格。
  int? _downSquare;

  /// 网格局部坐标 → 1D index（翻转感知）；8x8 外返回 null。
  int? _squareFromLocal(Offset pos) {
    final cell = widget.cellSize;
    if (pos.dx < 0 ||
        pos.dy < 0 ||
        pos.dx >= cell * kBoardCols ||
        pos.dy >= cell * kBoardRows) {
      return null;
    }
    final dcol = (pos.dx ~/ cell).clamp(0, kBoardCols - 1);
    final drow = (pos.dy ~/ cell).clamp(0, kBoardRows - 1);
    if (widget.flipped) {
      // 黑方视角：显示 (dcol, drow) ↔ 白方视角 (7-dcol, 7-drow)
      return (kBoardRows - 1 - drow) * kBoardCols + (kBoardCols - 1 - dcol);
    }
    return drow * kBoardCols + dcol;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // tapDown：透传 tap（选中-点击两段式；无拖动时才胜出）
      onTapDown: (d) {
        final hit = _squareFromLocal(d.localPosition);
        if (hit != null) widget.onSquareTap?.call(hit);
      },
      // panDown：按下瞬间记录起始格（拖动起点）
      onPanDown: (d) {
        _downSquare = _squareFromLocal(d.localPosition);
        _lastLocal = d.localPosition;
      },
      onPanStart: (d) {
        _lastLocal = d.localPosition;
        final hit = _downSquare;
        if (hit != null) widget.onDragStart(hit, d.localPosition);
      },
      onPanUpdate: (d) {
        _lastLocal = d.localPosition;
        widget.onDragUpdate?.call(
          _squareFromLocal(d.localPosition),
          d.localPosition,
        );
      },
      onPanEnd: (_) {
        final last = _lastLocal ?? Offset.zero;
        widget.onDragEnd(_squareFromLocal(last), last);
        _lastLocal = null;
        _downSquare = null;
      },
      // 系统取消（如被上层手势抢走）：按"棋盘外松手"结算 → 调用方弹回
      onPanCancel: () {
        final last = _lastLocal;
        if (last != null) widget.onDragEnd(null, last);
        _lastLocal = null;
        _downSquare = null;
      },
    );
  }
}

/// 字母 a-h 标签（底部）
class _FileLabels extends StatelessWidget {
  final bool flipped;
  final Color labelColor;
  final double cellSize;

  const _FileLabels({
    required this.flipped,
    required this.labelColor,
    required this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var col = 0; col < kBoardCols; col++) {
      // flipped 时：显示顺序与显示列对应反（a 仍在视觉上对应白方视角的 a 文件）
      final fileIdx = flipped ? (kBoardCols - 1 - col) : col;
      children.add(
        SizedBox(
          width: cellSize,
          height: double.infinity,
          child: Center(
            child: Text(
              kFiles[fileIdx],
              style: TextStyle(
                color: labelColor,
                fontSize: cellSize * 0.22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// 数字 1-8 标签（左侧）
class _RankLabels extends StatelessWidget {
  final bool flipped;
  final Color labelColor;
  final double cellSize;

  const _RankLabels({
    required this.flipped,
    required this.labelColor,
    required this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var row = 0; row < kBoardRows; row++) {
      // flipped 时：白方视角 rank 8 在最顶 → rank 1 在最底；
      // 翻转后白方视角 rank 1 在最顶，rank 8 在最底（黑方视角）
      final rankIdx = flipped ? (kBoardRows - 1 - row) : row;
      final rank = rankFromRow(rankIdx);
      children.add(
        SizedBox(
          height: cellSize,
          child: Center(
            child: Text(
              '$rank',
              style: TextStyle(
                color: labelColor,
                fontSize: cellSize * 0.22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Unicode 字符 fallback（当 skin.pieces 缺 key 时使用）
/// 委托共享 helper（chess_constants.chessPieceUnicodeFallback，
/// ChessPiece.errorBuilder / 升变面板同用一份映射）。
String _unicodeFallback(String key) => chessPieceUnicodeFallback(key);