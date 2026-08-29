// lib/core/chess/widgets/chess_board.dart
//
// 8x8 棋盘的纯渲染层（Stateless）。
//
// 责任：
//   · 8x8 两色格 + 坐标标签（a-h / 1-8，可翻转）+ 选中/上一步/合法走法/吃子高亮
//   · 把每个非空格子的 [BoardState.cells] 通过 [ChessSkin] 找 [ImageProvider]
//     渲染 [ChessPiece]
//   · tap 通过 [onSquareTap] 透传（1D index）
//
// 不负责：
//   · 走法生成（[ChessEngine]）
//   · 选中态管理（[ChessController]）
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
//   · [flipped] 默认 = (sideToMove == black)（保持旧行为：走子方在底）。
//     联机对局应显式传入"角色稳定"的 flipped（如 _myColor == black），
//     让视角整局稳定，而不是每走一步 180° 翻转。
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
  final PieceColor sideToMove;

  /// 是否翻转棋盘（黑方视角）。
  /// 联机对局由"角色"（我方颜色）驱动并整局稳定；
  /// 不传时默认 = (sideToMove == black)，保持旧行为（每步走子方在底）。
  final bool? flipped;

  /// 当前选中的 1D index（高亮最强）。
  final int? selectedSquare;

  /// 合法走法目标（1D index）—— 用作走法提示圆点 / 吃子圆圈。
  final Set<int> legalTargets;

  /// 上一步走法 —— from / to 用 lastMoveHighlight 着色。
  final Move? lastMove;

  /// 点击回调（1D index）。
  final void Function(int square)? onSquareTap;

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
    final flipped = this.flipped ?? sideToMove == PieceColor.black;
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

  const _BoardGrid({
    required this.state,
    required this.skin,
    required this.flipped,
    required this.cellSize,
    required this.colors,
    required this.selectedSquare,
    required this.legalTargets,
    required this.lastMove,
    required this.onSquareTap,
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
                      hasOpponent: _isOpponentOn(idx),
                      emptySquare: state.isEmpty(idx),
                      cellSize: cellSize,
                      legalMoveHint: colors.legalMoveHint,
                      captureHint: colors.captureHint,
                    ),
                  ),
                ),
              );
            }(),
          // 棋子层 —— IgnorePointer 让棋子不抢走下层格子的 tap
          for (var idx = 0; idx < kBoardSquares; idx++)
            if (!state.isEmpty(idx))
              () {
                final (col, row) = _displayOf(idx);
                final slot = state.slotAt(idx)!;
                final type = PieceSlot.unpackType(slot);
                final pieceColor = PieceSlot.unpackColorEnum(slot);
                final key = chessSkinKeyOf(pieceColor, type);
                final image = skin.pieces[key];
                if (image == null) {
                  // fallback：unicode 字符
                  return Positioned(
                    left: col * cellSize,
                    top: row * cellSize,
                    width: cellSize,
                    height: cellSize,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          _unicodeFallback(key),
                          style: TextStyle(fontSize: cellSize * 0.7),
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
                    child: ChessPiece(
                      image: image,
                      size: cellSize - pad * 2,
                    ),
                  ),
                );
              }(),
        ],
      ),
    );
    return board;
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

  bool _isOpponentOn(int idx) {
    final c = state.pieceColorAt(idx);
    if (c == null) return false;
    return c != state.sideToMove;
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

  const _LegalMarker({
    required this.isLegalTarget,
    required this.hasOpponent,
    required this.emptySquare,
    required this.cellSize,
    required this.legalMoveHint,
    required this.captureHint,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLegalTarget) return const SizedBox.shrink();
    // 吃子走法 → 圆圈；空格走法 → 圆点
    if (hasOpponent) {
      return Center(
        child: Container(
          width: cellSize * 0.85,
          height: cellSize * 0.85,
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
      return Center(
        child: Container(
          width: cellSize * 0.32,
          height: cellSize * 0.32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: legalMoveHint,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
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
/// key → FEN char → unicode symbol
String _unicodeFallback(String key) {
  // key 形如 'wK' / 'bp'；FEN char = type char，颜色决定大小写
  final isWhite = key.startsWith('w');
  final typeChar = key.substring(1).toLowerCase();
  final fenChar = isWhite ? typeChar.toUpperCase() : typeChar;
  return kUnicodePieces[fenChar] ?? '?';
}