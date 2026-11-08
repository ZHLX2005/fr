// 通知卡回归测试。
//
// 1. 时间文字不被裁掉（letterSpacing 实测/渲染不一致 → 换行 → 末字被切）
// 2. 图标 / 应用名的渐入动效：静态在左侧原位 → 拖动时极快移到左上角
//    → 归零 → 渐入
// 3. 各档位高度与原型公式一致
// 4. 通知数据一致（条数 / 标题 / 行数）
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/notification_pull/const_notification_pull.dart';
import 'package:xiaodouzi_fr/lab/demos/notification_pull/notification_pull_card.dart';

/// 实测一段文字的宽度（与卡片内部同口径）
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

        final Element ctx = tester.element(f.first);
        final TextStyle effective =
            DefaultTextStyle.of(ctx).style.merge(kTimeStyle);
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

  group('图标 / 应用名 渐入动效', () {
    /// 图标当前可见度
    double iconAlpha(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(
            of: find.byKey(const ValueKey<String>('notification-pull-icon')),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;

    /// 应用名当前可见度
    double nameAlpha(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(
            of: find.text(kAppName).first,
            matching: find.byType(Opacity),
          ),
        )
        .opacity;

    /// 静态态：图标**在左侧原位、完全可见**（它是卡片主体）；
    /// 应用名不可见（头部行高为 0，本来就无处可显）。
    testWidgets('静态态：图标完全可见，应用名不可见', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: NotificationPullCard())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(iconAlpha(tester), closeTo(1.0, 0.001),
          reason: '静态态图标在左侧原位且完全可见');
      expect(nameAlpha(tester), 0, reason: '静态态不该显示应用名');
    });

    /// 完全展开：图标与应用名都完全显形。
    testWidgets('完全展开时图标与应用名都完全显形', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: NotificationPullCard(initialStage: 'five')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(iconAlpha(tester), closeTo(1.0, 0.001));
      expect(nameAlpha(tester), closeTo(1.0, 0.001));
    });

    /// 关键回归：真实拖动手势下，图标必须**先归零再渐入**。
    ///
    /// 静态态图标在左侧原位、完全可见；一旦开始拖动，图标已极快移到第一行
    /// 左上角，此时必须归零（否则会看到大图标 + 小图标的重影），再渐入。
    testWidgets('拖动时图标先归零再渐入', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: NotificationPullCard())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 静态态：完全可见
      expect(iconAlpha(tester), closeTo(1.0, 0.001),
          reason: '静态态图标在左侧原位且完全可见');

      // 按下并拖动 —— 越过死区即进入拖动
      final TestGesture gesture =
          await tester.startGesture(const Offset(195, 300));
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // 拖动中：图标已归零（刚开始渐入，值很小）
      final double during = iconAlpha(tester);
      expect(during, lessThan(0.35),
          reason: '拖动刚开始图标应归零后渐入（实测 $during）');

      // 继续拖动：可见度应单调变深，直到完全显形
      final List<double> ramp = <double>[during];
      for (int i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        ramp.add(iconAlpha(tester));
      }
      for (int i = 1; i < ramp.length; i++) {
        expect(ramp[i], greaterThanOrEqualTo(ramp[i - 1]),
            reason: '拖动中可见度应单调不减：$ramp');
      }
      expect(ramp.last, closeTo(1.0, 0.001),
          reason: '拖到位后图标应完全显形');

      await gesture.up();
      await tester.pump();
    });

    /// 关键回归：**第一帧小正文的左右位置不变**。
    ///
    /// 左侧那块让位空间（52px）不能在切换瞬间被收走 —— 那会让小正文
    /// 「啪」地跳到最左边。缩进要等拖动起来后，连贯地收完。
    testWidgets('第一帧小正文左右位置不变，缩进随后连贯回收', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: NotificationPullCard())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      double rowLeft(WidgetTester t) =>
          t.getTopLeft(find.text('回忆坐标').first).dx;

      final double left0 = rowLeft(tester);

      final TestGesture gesture =
          await tester.startGesture(const Offset(195, 300));
      await gesture.moveBy(const Offset(0, 6));
      await tester.pump();

      // 第一帧：左右基本没动
      expect(rowLeft(tester), closeTo(left0, 1.0),
          reason: '第一帧小正文不该左右瞬移（$left0 → ${rowLeft(tester)}）');

      // 之后：缩进连贯回收（单调左移，最终收到最左）
      final List<double> lefts = <double>[rowLeft(tester)];
      for (int i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        lefts.add(rowLeft(tester));
      }
      for (int i = 1; i < lefts.length; i++) {
        expect(lefts[i], lessThanOrEqualTo(lefts[i - 1] + 0.01),
            reason: '缩进应单调回收：$lefts');
      }
      expect(lefts.last, closeTo(kPadL, 0.5),
          reason: '拖到位后文字应左对齐（$kPadL）');

      await gesture.up();
      await tester.pump();
    });

    /// 关键回归：**第一帧不能发生布局突变**。
    ///
    /// 图标从「左侧大字牌」迁到「第一行左上角小图标」这条通道，早前是按
    /// 头部对齐进度（ah）派生且用了极小的分母 —— 结果拖动头 4px 内就跳完，
    /// 视觉上像被弹射（用户反馈的「第一帧就发生了布局变化」）。
    ///
    /// 现在这条通道按**拖动像素**推进：第一帧（6px）只能挪动一点点，
    /// 且必须是一个连续的渐变过程，不允许某一步直接跳到位。
    testWidgets('拖动第一帧不发生布局突变（图标渐进迁移）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: NotificationPullCard())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      const Key iconKey = ValueKey<String>('notification-pull-icon');
      double size(WidgetTester t) => t.getSize(find.byKey(iconKey)).width;

      final TestGesture gesture =
          await tester.startGesture(const Offset(195, 300));
      await gesture.moveBy(const Offset(0, 6));
      await tester.pump();

      // 第一帧：布局**离散切换** —— 图标直接到位（40px 大字牌 → 18px 小图标）。
      // 这是刻意要的：一触发就换排布，逐帧 morph 反而显得拖不动。
      expect(size(tester), closeTo(18.0, 0.5),
          reason: '第一帧图标应直接切换到头部小图标（18px）');

      // 图标相对卡片的偏移在切换后保持不动（卡片本身在长高、居中，
      // 绝对坐标会变，所以要减去卡片顶边来比）。
      double iconOffsetInCard(WidgetTester t) =>
          t.getTopLeft(find.byKey(iconKey)).dy -
              t.getTopLeft(find.byType(NotificationPullCard)).dy;
      final List<double> offs = <double>[iconOffsetInCard(tester)];
      for (int i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 6));
        await tester.pump();
        offs.add(iconOffsetInCard(tester));
      }
      for (int i = 1; i < offs.length; i++) {
        expect(offs[i], closeTo(offs[i - 1], 0.01),
            reason: '切换到位后图标相对卡片的偏移应保持不动：$offs');
      }

      await gesture.up();
      await tester.pump();
    });

    /// 图标迁到第一行左上角：拖动推进到 26px 内完成，
    /// 且位移与拖动同步（不是第一帧就跳完）。
    testWidgets('图标迁到第一行左上角（与拖动同步推进）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: NotificationPullCard())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Size iconSize(WidgetTester t) => t.getSize(
            find.byKey(const ValueKey<String>('notification-pull-icon')),
          );
      Offset iconPos(WidgetTester t) => t.getTopLeft(
            find.byKey(const ValueKey<String>('notification-pull-icon')),
          );

      final Offset staticPos = iconPos(tester);

      final TestGesture gesture =
          await tester.startGesture(const Offset(195, 300));

      // 第一帧就切换到位（离散）：图标直接变成头部小图标并上移
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(iconSize(tester).width, closeTo(18.0, 0.5),
          reason: '拖动第一帧图标应切换到 18px 小图标');
      expect(iconPos(tester).dy, lessThan(staticPos.dy),
          reason: '拖动时图标应上移到第一行左上角');

      await gesture.up();
      await tester.pump();
    });
  });

  group('高度档位与原型一致', () {
    // 与原型的 measure() 公式逐项对应
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
    test('5 条，正文行数 2/1/2/1/1（与原型一致）', () {
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
