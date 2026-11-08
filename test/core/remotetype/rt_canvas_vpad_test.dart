// test/core/remotetype/rt_canvas_vpad_test.dart
//
// 虚拟手柄键区稳定性单测：
//   - 按住期间模块被卸载（旋转 / 切布局 / 退画布）→ dispose 补发松开，
//     防 PC 端虚拟手柄该键卡死在按下态（Listener 收不到 pointer cancel）。
//   - 松开事件在正常 up 路径只发一次（dispose 不重复补发）。
//   - 出厂几何（画布参考系）与编辑态逐键编排 / 幽灵键显隐。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_vpad.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart'
    show RtVpadKeyState, rtVpadKeyOrder;

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
    test('全键齐全；肩扳分侧竖排，ABXY 右上菱形，系统键居中偏上', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      expect(slots.keys.toSet(), rtVpadKeyOrder.toSet());

      // 肩扳：左右侧缘竖排（上肩下扳）
      final lb = slots['lb']!;
      final lt = slots['lt']!;
      final rt = slots['rt']!;
      final rb = slots['rb']!;
      expect(lb.dx, closeTo(lt.dx, 0.01));
      expect(rb.dx, closeTo(rt.dx, 0.01));
      expect(lb.dx, lessThan(rb.dx));
      expect(lb.dy, lessThan(lt.dy));
      expect(rb.dy, lessThan(rt.dy));

      // ABXY 菱形
      expect(slots['y']!.dy, lessThan(slots['a']!.dy));
      expect(slots['x']!.dx, lessThan(slots['b']!.dx));
      expect(slots['y']!.dx, closeTo(slots['a']!.dx, 0.01));
      expect(slots['x']!.dy, closeTo(slots['b']!.dy, 0.01));

      // 面键在右半区
      expect(slots['y']!.dx, greaterThan(box.width * 0.5));
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
    Future<List<({String key, Offset? center, double scale})>> pumpEditVpad(
      WidgetTester tester, {
      Map<String, RtVpadKeyState> keyStates = const {},
    }) async {
      final calls = <({String key, Offset? center, double scale})>[];
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
                  keyStates: keyStates,
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
        calls.first.center!.dx,
        greaterThan(before.dx / 300),
        reason: '向右拖 → 比例位右移',
      );
      expect(
        calls.first.center!.dy,
        closeTo(before.dy / 260, 0.02),
        reason: '水平拖动不改纵向',
      );
    });

    testWidgets('缩放落定（键无显式位）→ centerFraction 传 null 位置保持出厂', (
      tester,
    ) async {
      final calls = await pumpEditVpad(tester);
      final aCenter = tester.getCenter(find.text('A'));
      // 选中（点一下）→ 拉手出现在选中键右下角 → 从拉手中心拖拉手缩放。
      await tester.tapAt(aCenter);
      await tester.pump();
      final grip = tester.getCenter(find.byIcon(Icons.open_in_full));
      final gesture = await tester.startGesture(grip);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(calls.length, 1, reason: '缩放落定回写一次');
      expect(calls.first.key, 'a');
      expect(calls.first.center, isNull, reason: '出厂位键缩放不固化位置');
      expect(calls.first.scale, greaterThan(1.0), reason: '右拖拉手 = 放大');
    });

    testWidgets('轻点无位移 → 只选中不落盘', (tester) async {
      final calls = await pumpEditVpad(tester);
      final aCenter = tester.getCenter(find.text('A'));
      await tester.tapAt(aCenter);
      await tester.pump();
      expect(calls, isEmpty, reason: '纯点选不写 vpad');
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

  group('键级显隐（vpad 键编排态）', () {
    testWidgets('编辑态幽灵键点击开启（v=false → 回调 onKeyToggleVisible）', (
      tester,
    ) async {
      final toggled = <String>[];
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
                  keyStates: const {'a': RtVpadKeyState(v: false)},
                  onKey: ({button, trigger, required pressed}) {},
                  onKeyToggleVisible: (key) => toggled.add(key),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final ghost = find.byKey(const ValueKey('vpad-ghost:a'));
      expect(ghost, findsOneWidget, reason: '编辑态幽灵轮廓在场');
      expect(
        tester.getCenter(find.text('A')),
        equals(tester.getCenter(ghost)),
        reason: '幽灵键名照常显示',
      );
      await tester.tap(ghost);
      await tester.pump();
      expect(toggled, ['a'], reason: '点击幽灵 = 开键');
    });

    testWidgets('使用态幽灵不渲染（v=false 键使用态消失）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 260,
                child: RtCanvasVpad(
                  enabled: true,
                  keyStates: const {'a': RtVpadKeyState(v: false)},
                  onKey: ({button, trigger, required pressed}) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('A'), findsNothing);
    });

    testWidgets('键态带比例位 → 位置按画布比例渲染（出厂位键按出厂几何）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 260,
                child: RtCanvasVpad(
                  enabled: true,
                  keyStates: const {
                    'a': RtVpadKeyState(x: 0.10, y: 0.10, s: 1.5),
                  },
                  onKey: ({button, trigger, required pressed}) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // getCenter 是全局坐标：减去键区左上角（SizedBox 在窗口里居中）。
      final origin = tester.getTopLeft(find.byType(RtCanvasVpad));
      final center = tester.getCenter(find.text('A')) - origin;
      expect(center.dx, closeTo(300 * 0.10, 1.0), reason: 'x 比例位直接生效');
      expect(center.dy, closeTo(260 * 0.10, 1.0), reason: 'y 比例位直接生效');
    });
  });

  group('vpad 13 键（协议面键全量）', () {
    test('系统面键（BACK/GUIDE/START）居中偏上，在 ABXY 上方', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      const sys = ['back', 'guide', 'start'];
      for (final k in sys) {
        expect(slots[k]!.dy, lessThan(slots['y']!.dy), reason: '$k 在 ABXY 上方');
        expect(slots[k]!.dy, lessThan(box.height * 0.35), reason: '$k 偏上');
      }
      expect(slots['back']!.dx, lessThan(slots['guide']!.dx));
      expect(slots['guide']!.dx, lessThan(slots['start']!.dx));
    });

    test('摇杆键 L3 / R3 落在双摇之间偏下', () {
      const box = Size(300, 260);
      final slots = rtVpadDefaultSlots(box);
      expect(slots['l3']!.dx, lessThan(slots['r3']!.dx));
      expect(slots['l3']!.dx, greaterThan(box.width * 0.3));
      expect(slots['r3']!.dx, lessThan(box.width * 0.7));
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
