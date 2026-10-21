// test/lab/demos/remotetype/rt_canvas_vpad_test.dart
//
// 虚拟手柄键区稳定性单测：
//   - 按住期间模块被卸载（旋转 / 切布局 / 退画布）→ dispose 补发松开，
//     防 PC 端虚拟手柄该键卡死在按下态（Listener 收不到 pointer cancel）。
//   - 松开事件在正常 up 路径只发一次（dispose 不重复补发）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_canvas_vpad.dart';

void main() {
  testWidgets('按住期间模块被卸载 → dispose 补发松开', (tester) async {
    final events = <({String? button, String? trigger, bool pressed})>[];
    Widget host() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 300,
                child: RtCanvasVpad(
                  enabled: true,
                  onKey: ({button, trigger, required pressed}) =>
                      events.add((button: button, trigger: trigger, pressed: pressed)),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(host());
    final aCenter = tester.getCenter(find.text('A'));
    final gesture = await tester.startGesture(aCenter);
    await tester.pump();
    expect(
      events.where((e) => e.button == 'a' && e.pressed),
      isNotEmpty,
      reason: '按下回报 vpad_button a=true',
    );
    final downCount = events.length;

    // 不抬手直接卸载整个模块（模拟旋转 / 切布局时的重建）
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump();
    expect(
      events.where((e) => e.button == 'a' && !e.pressed),
      isNotEmpty,
      reason: 'dispose 补发松开（防卡键）',
    );

    // 收尾手势（监听者已不在，无副作用）
    await gesture.up();
    expect(events.length, downCount + 1,
        reason: '补发只发生一次：up 路径不再重复');
  });

  testWidgets('正常按下-松开：事件成对，不触发 dispose 补发', (tester) async {
    final events = <({String? button, String? trigger, bool pressed})>[];
    Widget host() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 300,
                child: RtCanvasVpad(
                  enabled: true,
                  onKey: ({button, trigger, required pressed}) =>
                      events.add((button: button, trigger: trigger, pressed: pressed)),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(host());
    final yCenter = tester.getCenter(find.text('Y'));
    final gesture = await tester.startGesture(yCenter);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final yEvents = events.where((e) => e.button == 'y').toList();
    expect(yEvents.length, 2, reason: '按下 + 松开成对');
    expect(yEvents.first.pressed, isTrue);
    expect(yEvents.last.pressed, isFalse);

    // 卸载：已松开，dispose 不补发
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump();
    expect(events.where((e) => e.button == 'y').length, 2,
        reason: '正常路径 dispose 静默');
  });
}
