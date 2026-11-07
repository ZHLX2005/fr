// 通知卡回归测试。
//
// 1. 时间文字不被裁掉（letterSpacing 实测/渲染不一致 → 换行 → 末字被切）
// 2. 各档位高度与 HTML 原型公式一致
// 3. 通知数据与 HTML 原型一致（条数 / 标题 / 行数）
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/notification_pull/const_notification_pull.dart';
import 'package:xiaodouzi_fr/lab/demos/notification_pull/notification_pull_card.dart';

/// 实测一段文字的宽度（与卡片内部 _textWidth 同口径）
double _measureWidth(String text, TextStyle style) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return tp.width;
}

/// 卡片在 [stage] 档位下的实际高度。
///
/// 用唯一 key 强制重建 State —— initialStage 只在 initState 生效，
/// 同一测试里连续 pump 不同档位时若复用 State，高度会停在第一次的值。
Future<double> _cardHeight(
  WidgetTester tester,
  String? stage,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: NotificationPullCard(
            key: ValueKey<String>('stage-$stage'),
            initialStage: stage,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  final Size s = tester.getSize(find.byType(NotificationPullCard));
  return s.height;
}

void main() {
  group('时间文字不被裁剪', () {
    testWidgets('每个时间串渲染宽度 == 文字自身宽度，且未超出行数', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: NotificationPullCard())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      for (final NotificationNotice n in kNotices) {
        final Finder f = find.text(n.time);
        expect(f.evaluate().isNotEmpty, isTrue,
            reason: '找不到时间文本 "${n.time}"');

        final RenderParagraph rp = tester.renderObject<RenderParagraph>(f.first);

        // 关键回归点：时间槽宽度必须由文字自身撑开，不能用「首帧预测量」。
        // CJK 字体异步加载，initState 量到的「昨天」只有 10.2px，
        // 字体到位后真实宽度 23px —— 用预测量当列宽会把末字裁掉。
        expect(rp.didExceedMaxLines, isFalse,
            reason: '时间 "${n.time}" 超出 1 行，末字被裁掉');

        // 渲染宽度应等于该文本在同样样式下的自然宽度（没有被容器压窄）
        final Element ctx = tester.element(f.first);
        final TextStyle effective = DefaultTextStyle.of(ctx).style.merge(kTimeStyle);
        final double natural = _measureWidth(n.time, effective);
        expect(rp.size.width, closeTo(natural, 0.01),
            reason: '时间 "${n.time}" 渲染宽度(${rp.size.width}) '
                '≠ 自然宽度($natural) → 容器压窄导致裁字');
      }
    });

    test('时间样式显式钉死 letterSpacing（不继承外层 DefaultTextStyle）', () {
      expect(kTimeStyle.letterSpacing, 0);
      expect(kPlusStyle.letterSpacing, 0);
      expect(kTitleStyle.letterSpacing, 0);
      expect(kInlineStyle.letterSpacing, 0);
      expect(kBodyStyle.letterSpacing, 0);
    });
  });

  group('高度档位与 HTML 原型一致', () {
    // 与 HTML measure() 的公式逐项对应
    const double padT = 14, padB = 14, gap = 14, gap0 = 3;
    const double compactRow = 20, titleLine = 20;

    testWidgets('折叠档 = padT + 三行紧凑 + padB', (tester) async {
      final double h = await _cardHeight(tester, null);
      expect(h, closeTo(padT + compactRow * 3 + gap0 * 2 + padB, 0.01));
    });

    testWidgets('three / four / five 逐档递增，且差值与公式一致',
        (tester) async {
      final double h0 = await _cardHeight(tester, null);
      final double h2 = await _cardHeight(tester, 'three');
      final double h3 = await _cardHeight(tester, 'four');
      final double h4 = await _cardHeight(tester, 'five');

      expect(h2, greaterThan(h0));
      expect(h3, greaterThan(h2));
      expect(h4, greaterThan(h3));

      // 第 4 条高度 = titleLine + 3 + 19*bodyLines
      final double fh3 = titleLine + 3 + 19.0 * kNotices[3].bodyLines;
      expect(h3 - h2, closeTo(gap + fh3, 0.01));

      final double fh4 = titleLine + 3 + 19.0 * kNotices[4].bodyLines;
      expect(h4 - h3, closeTo(gap + fh4, 0.01));
    });

    testWidgets('hN 直达任意高度', (tester) async {
      final double h = await _cardHeight(tester, 'h180');
      expect(h, closeTo(180, 0.01));
    });
  });

  group('通知数据', () {
    test('5 条，正文行数 2/1/2/1/1（与 HTML 实测一致）', () {
      expect(kNotices.length, 5);
      expect(
        kNotices.map((NotificationNotice n) => n.bodyLines).toList(),
        <int>[2, 1, 2, 1, 1],
      );
    });

    test('首行与第三行时间为箭头/+N 让位 21px', () {
      expect(kNotices[0].timeRight, 21);
      expect(kNotices[2].timeRight, 21);
      expect(kNotices[2].plus, isTrue);
    });
  });
}
