// test/core/remotetype/rt_canvas_stick_test.dart
//
// 模拟摇杆模块单测（vpad_axis · 斜向走位）：
//   - 轴向口径：右为 +x / 上为 +y（XInput / ViGEmBus 口径，LY 正值 = 上）
//   - 斜向：两轴同时上报（动作游戏要的斜向走位）
//   - 死区：|v| < 0.12 不上报（防微抖漂移）
//   - 松手 / 卸载都回中报 0（PC 端摇杆不回中 = 角色一直走）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_stick.dart';

void main() {
  Future<List<(String, double)>> pumpStick(
    WidgetTester tester, {
    String axes = 'l',
  }) async {
    final calls = <(String, double)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: RtCanvasStick(
                enabled: true,
                axes: axes,
                onAxis: (axis, value) => calls.add((axis, value)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return calls;
  }

  testWidgets('拖右 → lx 正；拖上 → ly 正（斜向：两轴同时上报）', (tester) async {
    final calls = await pumpStick(tester);
    final center = tester.getCenter(find.byType(RtCanvasStick));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(
      calls.any((c) => c.$1 == 'lx' && c.$2 > 0),
      isTrue,
      reason: '右拖 → lx 为正',
    );
    expect(calls.any((c) => c.$1 == 'ly' && c.$2 == 0), isTrue);

    // 斜向：右 + 上
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(
      calls.any((c) => c.$1 == 'lx' && c.$2 > 0),
      isTrue,
      reason: '斜向时 lx 仍为正',
    );
    expect(
      calls.any((c) => c.$1 == 'ly' && c.$2 > 0),
      isTrue,
      reason: '斜向时 ly 为正（XInput 口径：上为正）',
    );
    await gesture.up();
  });

  testWidgets('松手回中：两轴各报 0', (tester) async {
    final calls = await pumpStick(tester);
    final center = tester.getCenter(find.byType(RtCanvasStick));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final lastX = calls.lastWhere((c) => c.$1 == 'lx');
    final lastY = calls.lastWhere((c) => c.$1 == 'ly');
    expect(lastX.$2, 0);
    expect(lastY.$2, 0);
  });

  testWidgets('死区内轻推不上报（防微抖漂移）', (tester) async {
    final calls = await pumpStick(tester);
    final center = tester.getCenter(find.byType(RtCanvasStick));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(4, 0)); // 半径 100，4px 远在死区内
    await tester.pump();
    expect(calls.where((c) => c.$2 != 0), isEmpty);
    await gesture.up();
  });

  testWidgets('卸载时仍偏着 → 补报回中（防 PC 端角色一直走）', (tester) async {
    final calls = await pumpStick(tester);
    final center = tester.getCenter(find.byType(RtCanvasStick));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    // 不抬手直接卸载（旋转 / 切布局）
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump();
    final lastX = calls.lastWhere((c) => c.$1 == 'lx');
    expect(lastX.$2, 0, reason: '卸载补报回中');
  });

  testWidgets('右摇杆用 rx/ry 轴名', (tester) async {
    final calls = await pumpStick(tester, axes: 'r');
    final center = tester.getCenter(find.byType(RtCanvasStick));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(
      calls.any((c) => c.$1 == 'ry' && c.$2 < 0),
      isTrue,
      reason: '下拖 → ry 为负（上为正的 XInput 口径）',
    );
    expect(calls.any((c) => c.$1 == 'rx'), isTrue);
    await gesture.up();
  });
}
