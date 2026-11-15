import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_motion.dart';

/// 动效原语的**手感断言**。
///
/// 第 2 轮验收反馈要「足够 ios、足够 q 弹，比如使用贝塞尔曲线之类的方式」——
/// 「弹」不是形容词，它是数学：曲线必须**过冲**再回位。所以这里不截图、不比版式，
/// 直接采样 `Curve.transform(t)`，把这条手感钉成可回归的断言。
void main() {
  /// 采样一条曲线（0..1 之间 200 个点）。
  List<double> samples(Curve c) =>
      [for (var i = 0; i <= 200; i++) c.transform(i / 200)];

  group('曲线', () {
    test('snap 会过冲（q 弹的数学判据）', () {
      final v = samples(NxKvMotion.snap);
      final peak = v.reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(1.01), reason: '超过 1 才叫「弹」；equal 1 只是缓动');
      expect(peak, lessThan(1.20), reason: '过冲超过 20% 会像抽筋（elasticOut 就过头了）');
      // 落地：终点必须精准回到 1（不然布局会停在偏移上）
      expect(v.last, closeTo(1, 1e-6));
    });

    test('glide 不过冲，且是「起步猛、收尾软」', () {
      final v = samples(NxKvMotion.glide);
      expect(v.every((x) => x <= 1 + 1e-9), isTrue, reason: '位移/展开不该越界');
      // ease-out 的判据：中点已经走过大半
      expect(NxKvMotion.glide.transform(0.5), greaterThan(0.75));
      expect(v.last, closeTo(1, 1e-6));
    });

    test('三条曲线的时长按「跟手 → 常规 → 回弹」递增', () {
      expect(NxKvMotion.fast.inMilliseconds, lessThan(NxKvMotion.base.inMilliseconds));
      expect(NxKvMotion.base.inMilliseconds, lessThan(NxKvMotion.slow.inMilliseconds));
      // 都在 400ms 以内：超过就是「慢」，iOS 的手感上限大约在这里
      expect(NxKvMotion.slow.inMilliseconds, lessThanOrEqualTo(400));
    });
  });

  group('NxKvPress', () {
    Future<void> pumpBox(WidgetTester tester) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: NxKvPress(
                  onTap: () {},
                  child: Container(width: 120, height: 44, color: const Color(0xFFEEEEEE)),
                ),
              ),
            ),
          ),
        );

    testWidgets('按下缩到 0.97，松手回到 1', (tester) async {
      await pumpBox(tester);
      double targetScale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      expect(targetScale(), 1);

      final g = await tester.startGesture(tester.getCenter(find.byType(NxKvPress)));
      await tester.pump();
      expect(targetScale(), 0.97, reason: '按下要跟手');

      await g.up();
      await tester.pumpAndSettle();
      expect(targetScale(), 1, reason: '抬起弹回原大');
    });

    testWidgets('没有 onTap 时不缩放（纯展示行不该抖）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: NxKvPress(child: SizedBox(width: 80, height: 30)))),
      ));
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });
  });

  group('NxKvChevron / NxKvBadge', () {
    testWidgets('展开时箭头转 90°', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvChevron(open: true))));
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0.25);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvChevron(open: false))));
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0);
    });

    testWidgets('徽标：null / 空串什么都不画，— 照画', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvBadge(null))));
      expect(find.byType(Text), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvBadge(''))));
      expect(find.byType(Text), findsNothing, reason: '空串不该留下一个空胶囊');

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvBadge('—'))));
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('数字变了走缩放切换（同一个数字重绘不该弹）', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvBadge('2'))));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(tester.widget<Text>(find.text('2')).key, const ValueKey<String>('2'));

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxKvBadge('5'))));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
    });
  });
}
