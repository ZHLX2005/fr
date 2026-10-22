// test/core/remotetype/rt_canvas_vpad_test.dart
//
// 虚拟手柄键区稳定性单测：
//   - 按住期间模块被卸载（旋转 / 切布局 / 退画布）→ dispose 补发松开，
//     防 PC 端虚拟手柄该键卡死在按下态（Listener 收不到 pointer cancel）。
//   - 松开事件在正常 up 路径只发一次（dispose 不重复补发）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_vpad.dart';

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
              onKey: ({button, trigger, required pressed}) => events.add((
                button: button,
                trigger: trigger,
                pressed: pressed,
              )),
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
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump();
    expect(
      events.where((e) => e.button == 'a' && !e.pressed),
      isNotEmpty,
      reason: 'dispose 补发松开（防卡键）',
    );

    // 收尾手势（监听者已不在，无副作用）
    await gesture.up();
    expect(events.length, downCount + 1, reason: '补发只发生一次：up 路径不再重复');
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
              onKey: ({button, trigger, required pressed}) => events.add((
                button: button,
                trigger: trigger,
                pressed: pressed,
              )),
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
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump();
    expect(
      events.where((e) => e.button == 'y').length,
      2,
      reason: '正常路径 dispose 静默',
    );
  });
  // ═══ 编辑态逐键编排 ═══

  group('rtVpadDefaultSlots 出厂几何', () {
    test('八键齐全；肩键同排居上，ABXY 呈菱形（Y 上 / X 左 / B 右 / A 下）', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      expect(slots.keys.toSet(), rtVpadKeyOrder.toSet());

      // 肩键：同一行、x 递增
      final lb = slots['lb']!;
      final lt = slots['lt']!;
      final rt = slots['rt']!;
      final rb = slots['rb']!;
      expect(lb.dy, lt.dy);
      expect(lt.dy, rt.dy);
      expect(rt.dy, rb.dy);
      expect(lb.dx, lessThan(lt.dx));
      expect(lt.dx, lessThan(rt.dx));
      expect(rt.dx, lessThan(rb.dx));

      // ABXY 菱形
      expect(slots['y']!.dy, lessThan(slots['a']!.dy));
      expect(slots['x']!.dx, lessThan(slots['b']!.dx));
      expect(slots['y']!.dx, closeTo(slots['a']!.dx, 0.01));
      expect(slots['x']!.dy, closeTo(slots['b']!.dy, 0.01));

      // 肩键行在面键之上
      expect(lb.dy, lessThan(slots['y']!.dy));
    });

    test('所有键完整落在模块盒内', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      for (final entry in slots.entries) {
        final size = rtVpadDefaultKeySize(entry.key, box);
        expect(
          entry.value.dx - size.width / 2,
          greaterThanOrEqualTo(-0.01),
          reason: '${entry.key} 左溢出',
        );
        expect(
          entry.value.dx + size.width / 2,
          lessThanOrEqualTo(box.width + 0.01),
          reason: '${entry.key} 右溢出',
        );
        expect(
          entry.value.dy - size.height / 2,
          greaterThanOrEqualTo(-0.01),
          reason: '${entry.key} 上溢出',
        );
        expect(
          entry.value.dy + size.height / 2,
          lessThanOrEqualTo(box.height + 0.01),
          reason: '${entry.key} 下溢出',
        );
      }
    });
  });

  group('编辑态逐键编排', () {
    Future<List<({String key, Offset center, double scale})>> pumpEditVpad(
      WidgetTester tester,
    ) async {
      final calls = <({String key, Offset center, double scale})>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 260,
                child: RtCanvasVpad(
                  enabled: true,
                  editMode: true,
                  onKey: ({button, trigger, required pressed}) {},
                  onKeyTransform: (key, center, scale) =>
                      calls.add((key: key, center: center, scale: scale)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    testWidgets('点下即拖 → 回写该键中心比例', (tester) async {
      final calls = await pumpEditVpad(tester);
      final before = rtVpadDefaultSlots(const Size(300, 260))['a']!;
      final aCenter = tester.getCenter(find.text('A'));

      final gesture = await tester.startGesture(aCenter);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(calls.length, 1, reason: '拖动落定回写一次');
      expect(calls.first.key, 'a');
      expect(
        calls.first.center.dx,
        greaterThan(before.dx / 300),
        reason: '向右拖 → 比例位右移',
      );
      expect(
        calls.first.center.dy,
        closeTo(before.dy / 260, 0.02),
        reason: '水平拖动不改纵向',
      );
    });

    testWidgets('轻点无位移 → 只选中不落盘', (tester) async {
      final calls = await pumpEditVpad(tester);
      final aCenter = tester.getCenter(find.text('A'));
      await tester.tapAt(aCenter);
      await tester.pump();
      expect(calls, isEmpty, reason: '纯点选不写 buttons');
    });

    testWidgets('编辑态按压不发手柄事件（编排与触发不串台）', (tester) async {
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 260,
                child: RtCanvasVpad(
                  enabled: true,
                  editMode: true,
                  onKey: ({button, trigger, required pressed}) =>
                      events.add('${button ?? trigger}:$pressed'),
                  onKeyTransform: (key, center, scale) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final aCenter = tester.getCenter(find.text('A'));
      final gesture = await tester.startGesture(aCenter);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(events, isEmpty, reason: '编辑态按压不触发 vpad 事件');
    });
  });

  group('vpad 13 键（协议面键全量）', () {
    test('系统面键行（BACK/START/GUIDE）在肩键行下方、ABXY 上方', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      const sys = ['back', 'start', 'guide'];
      final shoulderY = slots['lb']!.dy;
      for (final k in sys) {
        expect(slots[k]!.dy, greaterThan(shoulderY), reason: '$k 在肩键行下方');
        expect(slots[k]!.dy, lessThan(slots['y']!.dy), reason: '$k 在 ABXY 上方');
      }
      expect(slots['back']!.dx, lessThan(slots['start']!.dx));
      expect(slots['start']!.dx, lessThan(slots['guide']!.dx));
    });

    test('摇杆键 L3 / R3 落在模块盒左右下角', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      expect(slots['l3']!.dx, lessThan(slots['r3']!.dx));
      expect(slots['l3']!.dx, lessThan(box.width * 0.2));
      expect(slots['r3']!.dx, greaterThan(box.width * 0.8));
      // 摇杆键在 ABXY 下方
      expect(slots['l3']!.dy, greaterThan(slots['a']!.dy));
    });

    testWidgets('BACK / START / GUIDE / L3 / R3 按下 → 对应 vpad_button', (
      tester,
    ) async {
      final events = <({String? button, String? trigger, bool pressed})>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 260,
                child: RtCanvasVpad(
                  enabled: true,
                  onKey: ({button, trigger, required pressed}) => events.add((
                    button: button,
                    trigger: trigger,
                    pressed: pressed,
                  )),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final label in const ['BACK', 'START', 'GUIDE', 'L3', 'R3']) {
        final center = tester.getCenter(find.text(label));
        final gesture = await tester.startGesture(center);
        await tester.pump();
        await gesture.up();
        await tester.pump();
      }
      final pressed = events
          .where((e) => e.pressed)
          .map((e) => e.button)
          .toSet();
      expect(pressed, {'back', 'start', 'guide', 'l3', 'r3'});
    });
  });
}
