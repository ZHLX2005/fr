// test/core/xiangqi/widgets/xiangqi_board_test.dart
//
// 中国象棋棋盘 / 棋子 widget 测试。
//
// 重点不是像素回归，而是**守住两个容易静默失效的点**：
//
//   1. flutter_svg 2.x 的后端 vector_graphics **不支持 <text> 元素** ——
//      会静默丢弃（不抛错）。若棋子 SVG 写错，棋子会变成没有字的空圆盘，
//      而测试若只断言"不抛异常"就发现不了。本文件因此断言 **SVG 源码里
//      必须含汉字 path**、且 **path 必须落在 0..100 viewBox 内**。
//   2. 棋盘是**交点式**布局（棋子压在棋盘线交点上），不是格子中心 ——
//      点击命中判定必须映射到最近的交点，且翻转视角下要正确反映射。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/constants/xiangqi_constants.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/board_state.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/piece.dart';
import 'package:xiaodouzi_fr/core/xiangqi/widgets/xiangqi_board.dart';
import 'package:xiaodouzi_fr/core/xiangqi/widgets/xiangqi_piece_glyphs.dart';
import 'package:xiaodouzi_fr/core/xiangqi/widgets/xiangqi_piece_svg.dart';

void main() {
  group('棋子字形 path', () {
    test('七子 + 楚河汉界全部有非空 path', () {
      const chars = [
        '帅', '将', '仕', '士', '相', '象', '马', '车', '炮', '兵', '卒',
        '楚', '河', '汉', '界',
      ];
      for (final ch in chars) {
        final d = kXiangqiGlyphPaths[ch];
        expect(d, isNotNull, reason: '$ch 缺字形 path');
        expect(d, isNotEmpty, reason: '$ch 字形 path 为空');
      }
    });

    test('字形坐标全部落在 0..100 viewBox 内（缩放/居中正确）', () {
      for (final entry in kXiangqiGlyphPaths.entries) {
        final numbers = RegExp(r'-?\d+(?:\.\d+)?')
            .allMatches(entry.value)
            .map((m) => double.parse(m.group(0)!))
            .toList();
        expect(numbers, isNotEmpty, reason: '${entry.key} 无坐标');
        // 逐对检查 x / y 配对（path 命令成对给出坐标）。
        for (var i = 0; i + 1 < numbers.length; i += 2) {
          final x = numbers[i];
          final y = numbers[i + 1];
          expect(x, inInclusiveRange(-0.5, 100.5),
              reason: '${entry.key} 的 x=$x 越界');
          expect(y, inInclusiveRange(-0.5, 100.5),
              reason: '${entry.key} 的 y=$y 越界');
        }
      }
    });
  });

  group('棋子 SVG', () {
    test('每个 (棋种, 颜色) 组合都生成含汉字 path 的 SVG', () {
      for (final type in XiangqiPieceType.values) {
        for (final color in XiangqiColor.values) {
          final piece = XiangqiPiece(color, type);
          final svg = XiangqiPieceArt.svgFor(piece);
          expect(svg, contains('<svg'), reason: '$piece 缺 svg 根节点');
          expect(svg, contains('<path d="'), reason: '$piece 缺汉字 path');
          expect(svg, contains('<circle'), reason: '$piece 缺圆盘');
          expect(
            svg,
            isNot(contains('<text')),
            reason: '$piece 不得用 <text>（vector_graphics 会静默丢弃）',
          );
          expect(
            svg,
            contains(kXiangqiGlyphPaths[piece.chineseName]),
            reason: '$piece 的 SVG 必须内嵌 ${piece.chineseName} 的字形 path',
          );
        }
      }
    });

    test('同一 (棋种, 颜色) 复用同一字符串（命中 flutter_svg 全局缓存）', () {
      final a = XiangqiPieceArt.svgFor(
        const XiangqiPiece(XiangqiColor.red, XiangqiPieceType.chariot),
      );
      final b = XiangqiPieceArt.svgFor(
        const XiangqiPiece(XiangqiColor.red, XiangqiPieceType.chariot),
      );
      expect(identical(a, b), isTrue);
    });

    test('红黑两方 SVG 不同（描边 / 字色不同）', () {
      final red = XiangqiPieceArt.svgFor(
        const XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse),
      );
      final black = XiangqiPieceArt.svgFor(
        const XiangqiPiece(XiangqiColor.black, XiangqiPieceType.horse),
      );
      expect(red, isNot(equals(black)));
    });

    testWidgets('棋子 widget 能渲染（SVG 能被 flutter_svg 解析）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                child: XiangqiPieceSvg(
                  piece: XiangqiPiece(
                    XiangqiColor.red,
                    XiangqiPieceType.general,
                  ),
                  size: 60,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(XiangqiPieceSvg), findsOneWidget);
    });

    testWidgets('棋子中心必须画出汉字像素（不是空圆盘）', (tester) async {
      // vector_graphics 静默丢弃 <text> / 解析失败时只留一个空圆盘 ——
      // 光断言"不抛异常"发现不了这种退化，故做像素级校验：
      // 取棋子中心 40% 区域（内圈内、汉字所在处）统计深色像素。
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: XiangqiPieceSvg(
                    piece: XiangqiPiece(
                      XiangqiColor.red,
                      XiangqiPieceType.general,
                    ),
                    size: 100,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var inkPixels = 0;
      var sampled = 0;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        // 中心 40% 区域（30%..70%）—— 内圈以内，汉字所在处
        final from = (100 * 0.30).round();
        final to = (100 * 0.70).round();
        for (var y = from; y < to; y++) {
          for (var x = from; x < to; x++) {
            final i = (y * 100 + x) * 4;
            sampled++;
            final r = bytes[i];
            final g = bytes[i + 1];
            final b = bytes[i + 2];
            // 墨色（红方 ink #A8261F）明显暗于象牙底（#F8EBD0）
            if (r < 210 && g < 150 && b < 150) inkPixels++;
          }
        }
        image.dispose();
      });

      expect(sampled, greaterThan(1000), reason: '采样区应足够大');
      expect(
        inkPixels,
        greaterThan(150),
        reason: '棋子中心应有汉字墨迹 —— 若为 0 说明字形没画出来（空圆盘）',
      );
    });
  });

  group('棋盘 widget', () {
    testWidgets('初始局面渲染 32 枚棋子且不抛异常', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: XiangqiBoard(
                state: XiangqiBoardState.initial(),
                onTapPoint: _noop,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(XiangqiPieceSvg), findsNWidgets(32));
    });

    testWidgets('楚河汉界 SVG 能渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: XiangqiBoard(
                state: XiangqiBoardState.initial(),
                onTapPoint: _noop,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(kXiangqiRiverTextSvg, contains('<path d="'));
      expect(kXiangqiRiverTextSvg, isNot(contains('<text')));
    });

    testWidgets('点击交点 → 上报正确的逻辑索引', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: XiangqiBoard(
                state: XiangqiBoardState.initial(),
                onTapPoint: taps.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 棋盘画布 9×10 格；交点位于 (0.5 + col, 0.5 + row) 格处。
      const cell = 360 / 9; // 画布按宽度定格（高度富余 → letterbox 居中）
      // 画布实际高 = 10 * cell，可能小于 400 → 垂直居中，需计入偏移。
      final canvasH = 10 * cell;
      final offsetY = (400 - canvasH) / 2;

      // 点「e0」交点（row 0, col 4）→ 索引 4
      final dx = (0.5 + 4) * cell;
      final dy = offsetY + (0.5 + 0) * cell;
      await tester.tapAt(tester.getCenter(find.byType(XiangqiBoard)) +
          Offset(dx - 180, dy - 200));
      await tester.pumpAndSettle();
      expect(taps, isNotEmpty);
      expect(taps.last, xiangqiIndex(0, 4));
    });

    testWidgets('黑方视角（flipped）点击 → 反映射到对侧交点', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: XiangqiBoard(
                state: XiangqiBoardState.initial(),
                flipped: true,
                onTapPoint: taps.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const cell = 360 / 9;
      final canvasH = 10 * cell;
      final offsetY = (400 - canvasH) / 2;

      // 翻转后视图左上角的交点 = 逻辑 (row 9, col 8) → 索引 89
      final dx = (0.5 + 0) * cell;
      final dy = offsetY + (0.5 + 0) * cell;
      await tester.tapAt(tester.getCenter(find.byType(XiangqiBoard)) +
          Offset(dx - 180, dy - 200));
      await tester.pumpAndSettle();
      expect(taps, isNotEmpty);
      expect(taps.last, xiangqiIndex(9, 8));
    });
  });
}

void _noop(int index) {}
