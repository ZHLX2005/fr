// test/lab/demos/remotetype/rt_canvas_dpad_test.dart
//
// 方向轮盘交互单测：
//   - 按下方向立即发一发 + 按住连发（160ms 周期）
//   - 按住滑到另一向 = 换向（旧向停发、新向立即发）
//   - 松手停发
//   - 未连接（enabled: false）不响应
//
// 判定口径与 RtCanvasDpad._dirAt 一致：相对轮盘中心，|dx|≥|dy| 取左右，
// 否则上下；中心死区（半径 25%）无方向。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_canvas_dpad.dart';

Future<void> pumpDpad(
  WidgetTester tester, {
  required ValueChanged<String> onDirection,
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: RtCanvasDpad(
              enabled: enabled,
              onDirection: onDirection,
              showLegend: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('按下右侧立即发 right，按住连发，滑到下方换向 down，松手停', (tester) async {
    final fired = <String>[];
    await pumpDpad(tester, onDirection: fired.add);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    final gesture = await tester.startGesture(center + const Offset(70, 0));
    await tester.pump();
    expect(fired, ['right'], reason: '按下立即发一发');

    // 按住连发：340ms 内应再发 ≥2 发（160ms 周期）
    await tester.pump(const Duration(milliseconds: 340));
    expect(fired.length, greaterThanOrEqualTo(3), reason: '按住应连发');
    expect(fired.every((d) => d == 'right'), isTrue);

    // 按住滑到下方 = 换向（旧向停发，新向立即发）
    await gesture.moveBy(const Offset(-70, 70));
    await tester.pump();
    expect(fired.last, 'down');

    // 松手 = 停发
    await gesture.up();
    await tester.pump();
    final count = fired.length;
    await tester.pump(const Duration(milliseconds: 340));
    expect(fired.length, count, reason: '松手后不应再发');
  });

  testWidgets('中心死区内按下不触发方向', (tester) async {
    final fired = <String>[];
    await pumpDpad(tester, onDirection: fired.add);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    // 死区 = 半径 25%（100px 轮盘 → 25px）；(15,0) 在死区内
    final gesture = await tester.startGesture(center + const Offset(15, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fired, isEmpty, reason: '死区内无方向');

    // 滑出死区（右侧 60px）→ 触发 right
    await gesture.moveBy(const Offset(45, 0));
    await tester.pump();
    expect(fired.last, 'right');

    await gesture.up();
    await tester.pump();
  });

  testWidgets('未连接（enabled: false）不响应', (tester) async {
    final fired = <String>[];
    await pumpDpad(tester, onDirection: fired.add, enabled: false);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    final gesture = await tester.startGesture(center + const Offset(70, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    expect(fired, isEmpty, reason: '置灰态不应发方向键');
  });
}
