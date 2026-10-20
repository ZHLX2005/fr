// lib/core/xiangqi/widgets/xiangqi_board.dart
//
// 中国象棋棋盘 widget（无状态，纯渲染 + 点击回调）。
//
// ## 棋盘几何 —— 棋子落在**线的交点**上（不是方格中心）
//
// 这是中国象棋与国际象棋 / 国际跳棋最直观的差别：
//
//   · 横线 10 条、纵线 9 条 → 交点 90 个，棋子压在交点上。
//   · 楚河汉界横在中间：**中间 7 条纵线在河界处断开**（河宽 1 格），
//     只有左右两条边线贯通 —— 与实物棋盘完全一致。
//   · 九宫（3×3 交点）在上下各画两条对角线。
//   · 炮位 / 兵位画「炮兵标记」四组折角小记号。
//
//   内部仍用 (row, col) 0-based 逻辑坐标：row 0 在顶部（黑方底线）、
//   row 9 在底部（红方底线）。渲染时按 `flipped` 做 180° 反映射。
//
// ## 棋子渲染
//
// 棋子是 **SVG**（`XiangqiPieceSvg`：圆盘 + 内环 + 汉字 path），
// 叠在棋盘线的 Stack 上层；棋盘线 / 河界 / 记号用 CustomPaint。
//
// ## 交互
//
//   · [onTapPoint] 上报被点的交点索引（1D 0..89）。
//   · 点击判定：交点周围半格内的点都归属该交点（取最近交点），
//     与实物"点线点"的手感一致。
//
// ## 视角（flipped）
//
//   · false（红方视角 / 默认）—— 红帅在下，黑将在上。
//   · true（黑方视角）—— 整盘 180° 翻转，黑将在下。
//     触摸坐标在同一变换里换算，避免"看到的与点到的错位"。
//
// 颜色走主题（深色模式自适应），不引入棋盘皮肤通道。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/xiangqi_constants.dart';
import '../models/board_state.dart';
import '../models/piece.dart';
import 'xiangqi_piece_glyphs.dart';
import 'xiangqi_piece_svg.dart';

/// 棋盘配色（由对局页按主题注入，默认走浅色木质棋具风）。
///
/// 主题豁免（S 级模块棋具令牌，逐项）：中国象棋棋具识别色系统，
/// 对齐 draughts / reversi 的 BoardThemeData 先例，不随主题漂移 ——
/// boardSurface/boardFrame 棋盘木色 · gridLine 墨线 · riverBand 河界底色 ·
/// highlight 选中 · legalTarget 可走点 · captureTarget 可吃点 ·
/// lastMove 上一手 · checkRing 被将军 · riverText 楚河汉界字色。
///
/// **棋子配色也在这里**（redPiece / blackPiece）—— 与 draughts 的
/// `DraughtsBoardPalette.whitePiece/blackPiece` 同款：棋盘与棋子是同一套
/// 棋具识别色系统，必须由**同一个 palette** 驱动，否则深色主题下会出现
/// 「深色棋盘 + 浅色棋子」的割裂，且形成两个真相源。
class XiangqiBoardPalette {
  final Color boardSurface;
  final Color boardFrame;
  final Color gridLine;
  final Color riverBand;
  final Color riverText;
  final Color highlight;
  final Color legalTarget;
  final Color captureTarget;
  final Color lastMove;
  final Color checkRing;

  /// 红方棋子配色
  final XiangqiPieceColors redPiece;

  /// 黑方棋子配色
  final XiangqiPieceColors blackPiece;

  const XiangqiBoardPalette({
    this.boardSurface = const Color(0xFFE8CFA0),
    this.boardFrame = const Color(0xFF8A6236),
    this.gridLine = const Color(0xFF5A3B1E),
    this.riverBand = const Color(0xFFEFDCB6),
    this.riverText = const Color(0xFF7A5730),
    this.highlight = const Color(0xFF3B82F6),
    this.legalTarget = const Color(0xFF2F7D32),
    this.captureTarget = const Color(0xFFB2312B),
    this.lastMove = const Color(0x6694A3B8),
    this.checkRing = const Color(0xFFDC2626),
    this.redPiece = XiangqiPieceColors.red,
    this.blackPiece = XiangqiPieceColors.black,
  });

  /// 浅色棋具预设（默认构造的具名引用，供房页色点等单源复用）
  static const XiangqiBoardPalette light = XiangqiBoardPalette();

  /// 深色主题下的棋具配色（棋盘与棋子**一起**变暗）
  static const XiangqiBoardPalette dark = XiangqiBoardPalette(
    boardSurface: Color(0xFF4A3A28),
    boardFrame: Color(0xFF2A2018),
    gridLine: Color(0xFFD8C49C),
    riverBand: Color(0xFF57452F),
    riverText: Color(0xFFC9B189),
    highlight: Color(0xFF60A5FA),
    legalTarget: Color(0xFF4ADE80),
    captureTarget: Color(0xFFF87171),
    lastMove: Color(0x66CBD5E1),
    checkRing: Color(0xFFF87171),
    redPiece: XiangqiPieceColors.redDark,
    blackPiece: XiangqiPieceColors.blackDark,
  );

  /// 取某方棋子配色
  XiangqiPieceColors pieceOf(XiangqiColor color) =>
      color == XiangqiColor.red ? redPiece : blackPiece;
}

/// 棋盘几何（以「格距 cell」为单位，1.0 = 相邻两条线之间的距离）。
class _Grid {
  /// 画布宽（格数）：8 列间距 + 左右各 0.5 格边距
  static const double canvasCols = 9.0;

  /// 画布高（格数）：9 行间距 + 上下各 0.5 格边距
  static const double canvasRows = 10.0;

  /// 棋盘区左上角（格）
  static const double origin = 0.5;

  /// 交点 → 视图坐标（格）
  static double viewX(int col, bool flipped) =>
      flipped ? origin + (kXiangqiCols - 1 - col) : origin + col;

  static double viewY(int row, bool flipped) =>
      flipped ? origin + (kXiangqiRows - 1 - row) : origin + row;
}

/// 中国象棋棋盘。
class XiangqiBoard extends StatelessWidget {
  const XiangqiBoard({
    super.key,
    required this.state,
    required this.onTapPoint,
    this.flipped = false,
    this.selectedIndex,
    this.legalTargets = const {},
    this.captureTargets = const {},
    this.lastMoveFrom,
    this.lastMoveTo,
    this.checkSquare,
    this.palette,
    this.interactive = true,
  });

  final XiangqiBoardState state;

  /// 被点击的交点索引（1D 0..89，未经翻转的"逻辑坐标"）
  final ValueChanged<int> onTapPoint;

  /// true = 黑方视角（180° 翻转）
  final bool flipped;

  /// 选中的交点索引
  final int? selectedIndex;

  /// 可落点集合（1D 索引）
  final Set<int> legalTargets;

  /// 可吃子落点集合（legalTargets 的子集）→ 用醒目色区分
  final Set<int> captureTargets;

  /// 上一手的起点 / 终点
  final int? lastMoveFrom;
  final int? lastMoveTo;

  /// 被将军的将/帅所在交点（画红环）
  final int? checkSquare;

  final XiangqiBoardPalette? palette;

  /// false = 只读（终局回顾 / 观战）
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final p = palette ??
        (Theme.of(context).brightness == Brightness.dark
            ? XiangqiBoardPalette.dark
            : const XiangqiBoardPalette());

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();

        final cell = math.min(
          maxW / _Grid.canvasCols,
          maxH / _Grid.canvasRows,
        );
        final canvasW = cell * _Grid.canvasCols;
        final canvasH = cell * _Grid.canvasRows;

        return Center(
          child: SizedBox(
            width: canvasW,
            height: canvasH,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: interactive
                  ? (details) {
                      final local = details.localPosition;
                      // 视图坐标 → 最近交点（半格归属）
                      final vx = (local.dx / cell) - _Grid.origin;
                      final vy = (local.dy / cell) - _Grid.origin;
                      var viewCol = vx.round();
                      var viewRow = vy.round();
                      viewCol = viewCol.clamp(0, kXiangqiCols - 1);
                      viewRow = viewRow.clamp(0, kXiangqiRows - 1);
                      // 视图 → 逻辑坐标（翻转时 180° 反映射）
                      final col = flipped ? kXiangqiCols - 1 - viewCol : viewCol;
                      final row = flipped ? kXiangqiRows - 1 - viewRow : viewRow;
                      onTapPoint(xiangqiIndex(row, col));
                    }
                  : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ① 棋盘线 / 河界 / 记号（CustomPaint）
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _XiangqiBoardPainter(
                        state: state,
                        palette: p,
                        flipped: flipped,
                        selectedIndex: selectedIndex,
                        legalTargets: legalTargets,
                        captureTargets: captureTargets,
                        lastMoveFrom: lastMoveFrom,
                        lastMoveTo: lastMoveTo,
                        checkSquare: checkSquare,
                      ),
                    ),
                  ),
                  // ② 楚河汉界（SVG 汉字，叠在河界上）
                  Positioned(
                    left: cell * _Grid.origin,
                    top: cell * (_Grid.origin + kXiangqiRiverRow),
                    width: cell * (kXiangqiCols - 1),
                    height: cell,
                    child: IgnorePointer(
                      child: SvgPicture.string(
                        kXiangqiRiverTextSvg,
                        fit: BoxFit.fill,
                        colorFilter: ColorFilter.mode(
                          p.riverText,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  // ③ 棋子（SVG）—— 配色由 palette 注入（深色主题下与棋盘一起变暗）
                  for (final (idx, piece) in state.occupied)
                    _pieceAt(idx, piece, cell, p),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pieceAt(
    int idx,
    XiangqiPiece piece,
    double cell,
    XiangqiBoardPalette palette,
  ) {
    final row = xiangqiRowOf(idx);
    final col = xiangqiColOf(idx);
    final size = cell * 0.92;
    final center = Offset(
      cell * _Grid.viewX(col, flipped) - size / 2,
      cell * _Grid.viewY(row, flipped) - size / 2,
    );
    return Positioned(
      left: center.dx,
      top: center.dy,
      width: size,
      height: size,
      child: RepaintBoundary(
        child: XiangqiPieceSvg(
          piece: piece,
          size: size,
          colors: palette.pieceOf(piece.color),
        ),
      ),
    );
  }
}

/// 棋盘线 / 河界 / 记号的绘制器。
class _XiangqiBoardPainter extends CustomPainter {
  _XiangqiBoardPainter({
    required this.state,
    required this.palette,
    required this.flipped,
    required this.selectedIndex,
    required this.legalTargets,
    required this.captureTargets,
    required this.lastMoveFrom,
    required this.lastMoveTo,
    required this.checkSquare,
  });

  final XiangqiBoardState state;
  final XiangqiBoardPalette palette;
  final bool flipped;
  final int? selectedIndex;
  final Set<int> legalTargets;
  final Set<int> captureTargets;
  final int? lastMoveFrom;
  final int? lastMoveTo;
  final int? checkSquare;

  // 炮位 / 兵位记号（逻辑坐标）
  static const List<(int, int)> _cannonPoints = [
    (2, 1), (2, 7), (7, 1), (7, 7),
  ];
  static const List<(int, int)> _pawnPoints = [
    (3, 0), (3, 2), (3, 4), (3, 6), (3, 8),
    (6, 0), (6, 2), (6, 4), (6, 6), (6, 8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _Grid.canvasCols;
    final originX = cell * _Grid.origin;
    final originY = cell * _Grid.origin;
    final gridW = cell * (kXiangqiCols - 1);
    final gridH = cell * (kXiangqiRows - 1);

    // 1) 木质底板 + 外框
    final frameRect = Rect.fromLTWH(
      cell * 0.16,
      cell * 0.16,
      size.width - cell * 0.32,
      size.height - cell * 0.32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, Radius.circular(cell * 0.18)),
      Paint()..color = palette.boardFrame,
    );
    final surfaceRect = Rect.fromLTWH(
      originX - cell * 0.30,
      originY - cell * 0.30,
      gridW + cell * 0.60,
      gridH + cell * 0.60,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(surfaceRect, Radius.circular(cell * 0.08)),
      Paint()..color = palette.boardSurface,
    );

    // 2) 河界底色（楚河汉界所在的横带）
    canvas.drawRect(
      Rect.fromLTWH(
        originX,
        originY + cell * kXiangqiRiverRow,
        gridW,
        cell,
      ),
      Paint()..color = palette.riverBand,
    );

    // 3) 棋盘线
    final line = Paint()
      ..color = palette.gridLine
      ..strokeWidth = cell * 0.035
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    // 3a) 横线 10 条（贯通）
    for (var row = 0; row < kXiangqiRows; row++) {
      final y = originY + cell * _viewRow(row);
      canvas.drawLine(Offset(originX, y), Offset(originX + gridW, y), line);
    }

    // 3b) 纵线 9 条 —— 中间 7 条在河界处断开，只有左右边线贯通
    for (var col = 0; col < kXiangqiCols; col++) {
      final x = originX + cell * _viewCol(col);
      final isEdge = col == 0 || col == kXiangqiCols - 1;
      if (isEdge) {
        canvas.drawLine(
          Offset(x, originY),
          Offset(x, originY + gridH),
          line,
        );
      } else {
        // 上半段：row 0 → row 4
        canvas.drawLine(
          Offset(x, originY),
          Offset(x, originY + cell * kXiangqiRiverRow),
          line,
        );
        // 下半段：row 5 → row 9
        canvas.drawLine(
          Offset(x, originY + cell * (kXiangqiRiverRow + 1)),
          Offset(x, originY + gridH),
          line,
        );
      }
    }

    // 4) 九宫对角线
    void palace(int minRow) {
      final r0 = originY + cell * _viewRow(minRow);
      final r1 = originY + cell * _viewRow(minRow + 2);
      final c0 = originX + cell * _viewCol(3);
      final c1 = originX + cell * _viewCol(5);
      canvas.drawLine(Offset(c0, r0), Offset(c1, r1), line);
      canvas.drawLine(Offset(c1, r0), Offset(c0, r1), line);
    }

    palace(0);
    palace(7);

    // 5) 炮位 / 兵位记号
    for (final (row, col) in _cannonPoints) {
      _drawCornerMarks(canvas, line, originX, originY, cell, row, col);
    }
    for (final (row, col) in _pawnPoints) {
      _drawCornerMarks(canvas, line, originX, originY, cell, row, col);
    }

    // 6) 上一手高亮（起止两点）
    if (lastMoveFrom != null || lastMoveTo != null) {
      final lm = Paint()
        ..color = palette.lastMove
        ..isAntiAlias = true;
      for (final idx in [lastMoveFrom, lastMoveTo]) {
        if (idx == null) continue;
        final c = _pointOf(idx, originX, originY, cell);
        canvas.drawRect(
          Rect.fromCenter(
            center: c,
            width: cell * 0.86,
            height: cell * 0.86,
          ),
          lm,
        );
      }
    }

    // 7) 选中环
    if (selectedIndex != null) {
      final c = _pointOf(selectedIndex!, originX, originY, cell);
      canvas.drawCircle(
        c,
        cell * 0.52,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.07
          ..color = palette.highlight
          ..isAntiAlias = true,
      );
    }

    // 8) 可走点标记（空心圆环；吃子点用醒目色实心环）
    for (final idx in legalTargets) {
      final c = _pointOf(idx, originX, originY, cell);
      final isCapture = captureTargets.contains(idx);
      canvas.drawCircle(
        c,
        cell * (isCapture ? 0.30 : 0.26),
        Paint()
          ..style = isCapture ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = cell * 0.07
          ..color = isCapture ? palette.captureTarget : palette.legalTarget
          ..isAntiAlias = true,
      );
    }

    // 9) 被将军红环
    if (checkSquare != null) {
      final c = _pointOf(checkSquare!, originX, originY, cell);
      canvas.drawCircle(
        c,
        cell * 0.54,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.075
          ..color = palette.checkRing
          ..isAntiAlias = true,
      );
    }
  }

  // 逻辑 row → 视图行号（翻转时 180° 反映射）
  int _viewRow(int row) => flipped ? kXiangqiRows - 1 - row : row;

  // 逻辑 col → 视图列号（翻转时 180° 反映射）
  int _viewCol(int col) => flipped ? kXiangqiCols - 1 - col : col;

  /// 逻辑索引 → 视图坐标（px）
  Offset _pointOf(int index, double originX, double originY, double cell) {
    final row = xiangqiRowOf(index);
    final col = xiangqiColOf(index);
    return Offset(
      originX + cell * _viewCol(col),
      originY + cell * _viewRow(row),
    );
  }

  /// 炮位 / 兵位记号：在交点四角画折角短线（边线处只画内侧两角）。
  void _drawCornerMarks(
    Canvas canvas,
    Paint line,
    double originX,
    double originY,
    double cell,
    int row,
    int col,
  ) {
    const near = 0.13;
    const far = 0.31;
    final px = originX + cell * _viewCol(col);
    final py = originY + cell * _viewRow(row);

    for (final dr in [-1, 1]) {
      for (final dc in [-1, 1]) {
        // 越界方向（棋盘左右外沿）不画
        final viewCol = _viewCol(col);
        final viewRow = _viewRow(row);
        if (dc < 0 && viewCol == 0) continue;
        if (dc > 0 && viewCol == kXiangqiCols - 1) continue;
        if (dr < 0 && viewRow == 0) continue;
        if (dr > 0 && viewRow == kXiangqiRows - 1) continue;

        final hx = px + dc * cell * near;
        final hy = py + dr * cell * near;
        final fx = px + dc * cell * far;
        final fy = py + dr * cell * far;

        // 横段：(near, far) → (far, far)
        canvas.drawLine(
          Offset(hx, fy),
          Offset(fx, fy),
          line,
        );
        // 竖段：(far, near) → (far, far)
        canvas.drawLine(
          Offset(fx, hy),
          Offset(fx, fy),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _XiangqiBoardPainter old) =>
      old.state != state ||
      old.flipped != flipped ||
      old.selectedIndex != selectedIndex ||
      !_setEquals(old.legalTargets, legalTargets) ||
      !_setEquals(old.captureTargets, captureTargets) ||
      old.lastMoveFrom != lastMoveFrom ||
      old.lastMoveTo != lastMoveTo ||
      old.checkSquare != checkSquare ||
      old.palette != palette;

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.every(b.contains);
}

/// 楚河汉界 —— SVG 汉字（viewBox 0 0 800 100，四个字横向排布）。
///
/// 字形 path 与棋子同源（Noto Serif SC 轮廓，见 xiangqi_piece_glyphs.dart），
/// 这里放大到整条河界宽度。颜色由棋盘层用 `ColorFilter` 注入。
///
/// 非 const：字符串里要索引 `kXiangqiGlyphPaths`（map 取值不是常量表达式），
/// 所以在首次访问时构造一次。
final String kXiangqiRiverTextSvg = _buildRiverTextSvg();

String _buildRiverTextSvg() {
  String glyph(String ch) =>
      '<g transform="translate(${65 + 200 * _riverOrder.indexOf(ch)} 15) '
      'scale(0.7)"><path d="${kXiangqiGlyphPaths[ch] ?? ''}" fill="#000"/></g>';
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 100">'
      '${glyph('楚')}${glyph('河')}${glyph('汉')}${glyph('界')}'
      '</svg>';
}

/// 河界四字的排布顺序（对应 viewBox 中 x = 100 / 300 / 500 / 700 的中心）。
const List<String> _riverOrder = ['楚', '河', '汉', '界'];
