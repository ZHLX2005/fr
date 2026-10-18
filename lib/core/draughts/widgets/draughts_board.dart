// lib/core/draughts/widgets/draughts_board.dart
//
// 国际跳棋 10×10 棋盘 widget（无状态，纯渲染 + 点击回调）。
//
// 交互（对局页负责状态，本 widget 只渲染 + 上报点击）：
//   · [onTapSquare] 上报被点的格索引（1D 0..99）。
//   · [selectedSquare] 高亮选中子；[legalTargets] 高亮可落点；
//     [lastMovePath] 高亮对手/自己上一手路径。
//
// 吃子视觉（激活 palette.captureHint 红色通道）：
//   · [captureTargets] 选中的吃子子落点 → 红点（与安静落点的蓝点区分）。
//   · [mustCapturePieces] 有吃子义务的己方子 → 红描边环（必动提示）。
//   · [threatenedSquares] 选中子的吃子链将被吃掉的对方子 → 红描边环。
//
// 视角（flipped）：
//   · false（白方视角 / 默认）—— 白子在下（row 9），与 FEN 视角一致。
//   · true（黑方视角）—— 整盘 180° 翻转，让黑子在下。
//   触摸坐标在同一变换里换算，避免"看到的与点到的错位"。
//
// 颜色走主题（深色模式自适应），不引入棋盘皮肤通道（本期不做换肤）。

import 'package:flutter/material.dart';

import '../constants/draughts_constants.dart';
import '../models/board_state.dart';
import '../models/piece.dart';

/// 棋盘配色（由对局页按主题注入，默认走浅色棋具风）。
///
/// 主题豁免（S 级模块棋具令牌，逐项）：跳棋棋具识别色系统，
/// 对齐 surround_game/reversi 的 BoardThemeData 先例，不随主题漂移 ——
/// darkSquare/lightSquare 棋盘格木色 · whitePiece/blackPiece 棋子色 ·
/// whitePieceBorder/blackPieceBorder 棋子描边 ·
/// highlight/captureHint/lastMove 走子提示色。
class DraughtsBoardPalette {
  final Color darkSquare;
  final Color lightSquare;
  final Color whitePiece;
  final Color blackPiece;
  final Color whitePieceBorder;
  final Color blackPieceBorder;
  final Color highlight;
  final Color captureHint;
  final Color lastMove;

  const DraughtsBoardPalette({
    this.darkSquare = const Color(0xFF6D4C33),
    this.lightSquare = const Color(0xFFEBD9B4),
    this.whitePiece = const Color(0xFFF7F3E8),
    this.blackPiece = const Color(0xFF2A2A2E),
    this.whitePieceBorder = const Color(0xFF8A7B5C),
    this.blackPieceBorder = const Color(0xFF101014),
    this.highlight = const Color(0xFF3B82F6),
    this.captureHint = const Color(0xFFEF4444),
    this.lastMove = const Color(0x6684CC16),
  });

  /// 浅色棋具预设（默认构造的具名引用，供房页色点等单源复用）
  static const DraughtsBoardPalette light = DraughtsBoardPalette();

  /// 深色主题下的棋具配色
  static const DraughtsBoardPalette dark = DraughtsBoardPalette(
    darkSquare: Color(0xFF3A2E24),
    lightSquare: Color(0xFF6B5B48),
    whitePiece: Color(0xFFE8E2D4),
    blackPiece: Color(0xFF1B1B1F),
    whitePieceBorder: Color(0xFF6E6250),
    blackPieceBorder: Color(0xFF000000),
  );
}

class DraughtsBoard extends StatelessWidget {
  const DraughtsBoard({
    super.key,
    required this.state,
    required this.onTapSquare,
    this.flipped = false,
    this.selectedSquare,
    this.legalTargets = const {},
    this.lastMovePath = const {},
    this.captureTargets = const {},
    this.mustCapturePieces = const {},
    this.threatenedSquares = const {},
    this.palette,
    this.interactive = true,
  });

  final DraughtsBoardState state;

  /// 被点击的格索引（1D 0..99，未经翻转的"逻辑坐标"）
  final ValueChanged<int> onTapSquare;

  /// true = 黑方视角（180° 翻转）
  final bool flipped;

  final int? selectedSquare;
  final Set<int> legalTargets;
  final Set<int> lastMovePath;

  /// 选中吃子子的落点（legalTargets 的子集）→ 红点。
  final Set<int> captureTargets;

  /// 有吃子义务的己方子 → 红描边环。
  final Set<int> mustCapturePieces;

  /// 选中子的吃子链将被吃掉的对方子 → 红描边环。
  final Set<int> threatenedSquares;

  final DraughtsBoardPalette? palette;

  /// false = 只读（终局回顾 / 观战）
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final p = palette ??
        (Theme.of(context).brightness == Brightness.dark
            ? DraughtsBoardPalette.dark
            : const DraughtsBoardPalette());

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          final cell = size / kDraughtsCols;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: interactive
                ? (details) {
                    final local = details.localPosition;
                    final col = (local.dx / cell).floor();
                    final row = (local.dy / cell).floor();
                    if (row < 0 || row >= kDraughtsRows) return;
                    if (col < 0 || col >= kDraughtsCols) return;
                    // 视图坐标 → 逻辑坐标（翻转时 180° 反映射）
                    final lr = flipped ? kDraughtsRows - 1 - row : row;
                    final lc = flipped ? kDraughtsCols - 1 - col : col;
                    onTapSquare(draughtsIndex(lr, lc));
                  }
                : null,
            child: CustomPaint(
              size: Size.square(size),
              painter: _DraughtsBoardPainter(
                state: state,
                palette: p,
                flipped: flipped,
                selectedSquare: selectedSquare,
                legalTargets: legalTargets,
                lastMovePath: lastMovePath,
                captureTargets: captureTargets,
                mustCapturePieces: mustCapturePieces,
                threatenedSquares: threatenedSquares,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DraughtsBoardPainter extends CustomPainter {
  _DraughtsBoardPainter({
    required this.state,
    required this.palette,
    required this.flipped,
    required this.selectedSquare,
    required this.legalTargets,
    required this.lastMovePath,
    required this.captureTargets,
    required this.mustCapturePieces,
    required this.threatenedSquares,
  });

  final DraughtsBoardState state;
  final DraughtsBoardPalette palette;
  final bool flipped;
  final int? selectedSquare;
  final Set<int> legalTargets;
  final Set<int> lastMovePath;
  final Set<int> captureTargets;
  final Set<int> mustCapturePieces;
  final Set<int> threatenedSquares;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kDraughtsCols;

    // 视图坐标 → 逻辑坐标（翻转时 180° 反映射）
    int lr(int viewRow) => flipped ? kDraughtsRows - 1 - viewRow : viewRow;
    int lc(int viewCol) => flipped ? kDraughtsCols - 1 - viewCol : viewCol;

    // 1) 格子底色
    final light = Paint()..color = palette.lightSquare;
    final dark = Paint()..color = palette.darkSquare;
    for (var viewRow = 0; viewRow < kDraughtsRows; viewRow++) {
      for (var viewCol = 0; viewCol < kDraughtsCols; viewCol++) {
        final rect = Rect.fromLTWH(
          viewCol * cell,
          viewRow * cell,
          cell,
          cell,
        );
        // 逻辑深浅由逻辑坐标决定（翻转不改变棋具本身的明暗）
        final isDark = (lr(viewRow) + lc(viewCol)) % 2 == 1;
        canvas.drawRect(rect, isDark ? dark : light);
      }
    }

    // 2) 上一手路径高亮
    if (lastMovePath.isNotEmpty) {
      final last = Paint()..color = palette.lastMove;
      for (final idx in lastMovePath) {
        final v = _viewOf(idx);
        canvas.drawRect(
          Rect.fromLTWH(v.$2 * cell, v.$1 * cell, cell, cell),
          last,
        );
      }
    }

    // 3) 选中格高亮
    if (selectedSquare != null) {
      final v = _viewOf(selectedSquare!);
      canvas.drawRect(
        Rect.fromLTWH(v.$2 * cell, v.$1 * cell, cell, cell),
        Paint()..color = palette.highlight.withValues(alpha: 0.45),
      );
    }

    // 4) 可落点提示：安静落点蓝点；吃子落点红点（captureHint，醒目区分）。
    final hint = Paint()..color = palette.highlight.withValues(alpha: 0.75);
    final captureDot = Paint()
      ..color = palette.captureHint.withValues(alpha: 0.85);
    for (final idx in legalTargets) {
      final v = _viewOf(idx);
      canvas.drawCircle(
        Offset(v.$2 * cell + cell / 2, v.$1 * cell + cell / 2),
        captureTargets.contains(idx) ? cell * 0.17 : cell * 0.16,
        captureTargets.contains(idx) ? captureDot : hint,
      );
    }

    // 5) 棋子
    for (final (idx, piece) in state.occupied) {
      if (draughtsSquareNumberOfIndex(idx) < 0) continue; // 浅色格不该有子
      final v = _viewOf(idx);
      _paintPiece(
        canvas,
        Offset(v.$2 * cell + cell / 2, v.$1 * cell + cell / 2),
        cell * 0.36,
        piece,
      );
    }

    // 6) 必动子描边环（有吃子义务的己方子，套在子外）
    if (mustCapturePieces.isNotEmpty) {
      final mustRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.05
        ..color = palette.captureHint
        ..isAntiAlias = true;
      for (final idx in mustCapturePieces) {
        final v = _viewOf(idx);
        canvas.drawCircle(
          Offset(v.$2 * cell + cell / 2, v.$1 * cell + cell / 2),
          cell * 0.42,
          mustRing,
        );
      }
    }

    // 7) 被威胁子描边环（选中子的吃子链将吃掉的对方子，贴子边缘）
    if (threatenedSquares.isNotEmpty) {
      final threatRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.045
        ..color = palette.captureHint.withValues(alpha: 0.9)
        ..isAntiAlias = true;
      for (final idx in threatenedSquares) {
        final v = _viewOf(idx);
        canvas.drawCircle(
          Offset(v.$2 * cell + cell / 2, v.$1 * cell + cell / 2),
          cell * 0.37,
          threatRing,
        );
      }
    }
  }

  /// 逻辑索引 → 视图 (row, col)
  (int, int) _viewOf(int index) {
    final r = draughtsRowOf(index);
    final c = draughtsColOf(index);
    if (flipped) {
      return (kDraughtsRows - 1 - r, kDraughtsCols - 1 - c);
    }
    return (r, c);
  }

  void _paintPiece(Canvas canvas, Offset center, double radius, DraughtsPiece piece) {
    final isWhite = piece.isWhite;
    final fill = Paint()
      ..color = isWhite ? palette.whitePiece : palette.blackPiece
      ..isAntiAlias = true;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18
      ..color = isWhite ? palette.whitePieceBorder : palette.blackPieceBorder
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius, fill);

    if (piece.isKing) {
      // 王：内圈 + 顶部短横（王冠意象），足够在小尺寸下辨识
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.14
        ..color = isWhite
            ? palette.blackPiece.withValues(alpha: 0.7)
            : palette.whitePiece.withValues(alpha: 0.8)
        ..isAntiAlias = true;
      canvas.drawCircle(center, radius * 0.58, ring);
    }

    canvas.drawCircle(center, radius, border);
  }

  @override
  bool shouldRepaint(covariant _DraughtsBoardPainter old) =>
      old.state != state ||
      old.flipped != flipped ||
      old.selectedSquare != selectedSquare ||
      !_setEquals(old.legalTargets, legalTargets) ||
      !_setEquals(old.lastMovePath, lastMovePath) ||
      !_setEquals(old.captureTargets, captureTargets) ||
      !_setEquals(old.mustCapturePieces, mustCapturePieces) ||
      !_setEquals(old.threatenedSquares, threatenedSquares) ||
      old.palette != palette;

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.every(b.contains);
}
