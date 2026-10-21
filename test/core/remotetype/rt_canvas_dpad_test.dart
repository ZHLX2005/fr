// test/core/remotetype/rt_canvas_dpad_test.dart
//
// 方向轮盘交互单测（vpad 十字键语义）：
//   - 按到某向立即回报该向一次（虚拟手柄保持状态，**不连发**）
//   - 按住滑到另一向 = 换向（旧向停、新向回报）
//   - 松手 / 滑回中心死区 = 回报 null（映射 vpad_dpad 'none' 回中）
//   - 未连接（enabled: false）不响应
//
// 判定口径与 RtCanvasDpad._dirAt 一致：相对轮盘中心，|dx|≥|dy| 取左右，
// 否则上下；中心死区（半径 25%）无方向。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_dpad.dart';

Future<void> pumpDpad(
  WidgetTester tester, {
  required ValueChanged<String?> onDirection,
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
  testWidgets('按下右侧立即回报 right（只一发，状态由虚拟手柄保持）', (tester) async {
    final fired = <String?>[];
    await pumpDpad(tester, onDirection: fired.add);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    final gesture = await tester.startGesture(center + const Offset(70, 0));
    await tester.pump();
    expect(fired, ['right']);

    // 按住 1 秒不连发（vpad 状态型指令）
    await tester.pump(const Duration(seconds: 1));
    expect(fired, ['right'], reason: '按住不连发');
    await gesture.up();
  });

  testWidgets('按住滑到下方换向 down；松手回报 null 回中', (tester) async {
    final fired = <String?>[];
    await pumpDpad(tester, onDirection: fired.add);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    final gesture = await tester.startGesture(center + const Offset(70, 0));
    await tester.pump();
    // 滑到下方 = 换向
    await gesture.moveBy(const Offset(-70, 70));
    await tester.pump();
    expect(fired, ['right', 'down']);
    // 同向再移动不重复回报
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    expect(fired, ['right', 'down'], reason: '同方向不重复回报');
    // 松手 = 回中
    await gesture.up();
    await tester.pump();
    expect(fired, ['right', 'down', null]);
  });

  testWidgets('中心死区内按下不触发方向；滑出死区才回报', (tester) async {
    final fired = <String?>[];
    await pumpDpad(tester, onDirection: fired.add);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    // 死区 = 半径 25%（100px 轮盘 → 25px）；(15,0) 在死区内
    final gesture = await tester.startGesture(center + const Offset(15, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fired, isEmpty, reason: '死区内无方向');

    // 滑出死区（右侧 60px）→ 回报 right
    await gesture.moveBy(const Offset(45, 0));
    await tester.pump();
    expect(fired, ['right']);

    await gesture.up();
    await tester.pump();
    expect(fired, ['right', null]);
  });

  testWidgets('未连接（enabled: false）不响应', (tester) async {
    final fired = <String?>[];
    await pumpDpad(tester, onDirection: fired.add, enabled: false);

    final center = tester.getCenter(find.byType(RtCanvasDpad));
    final gesture = await tester.startGesture(center + const Offset(70, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    expect(fired, isEmpty, reason: '置灰态不应回报方向');
  });
}
