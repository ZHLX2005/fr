// test/core/remotetype/rt_layouts_card_test.dart
//
// 设置页「布局大卡」的行为锁：
//   · 双组渲染（竖屏在上、横屏在下），可用性由分组表达；
//   · 点行 = 切该组激活（回调带组朝向）；
//   · 固定布局（写字）无 ⋯；内置菜单只有 编辑/恢复出厂；自定义多 改名/删除。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/template/rt_canvas_presets.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/template/rt_canvas_template_keyboard.dart'
    show kRtCanvasTemplateKeyboard;
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart';
import 'package:xiaodouzi_fr/core/remotetype/settings/rt_layouts_card.dart';

RtCanvasLayouts _builtinLayouts() => const RtCanvasLayouts(
  list: kRtCanvasBuiltinPresets,
  activeId: kRtCanvasPresetTouchpad,
);

Future<void> _pump(
  WidgetTester tester, {
  required RtCanvasLayouts layouts,
  required void Function(String orientation, String id) onSwitch,
  bool canEditOnCanvas = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            RtLayoutsCard(
              layouts: layouts,
              canEditOnCanvas: canEditOnCanvas,
              onSwitch: onSwitch,
              onReorder: (_, _, _) {},
              onResetBuiltin: (_) {},
              onRename: (_, _) {},
              onDelete: (_) {},
              onEditOnCanvas: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('双组渲染：竖屏组在上、横屏组在下；写字不进横屏组', (tester) async {
    await _pump(tester, layouts: _builtinLayouts(), onSwitch: (_, _) {});
    expect(find.text('竖屏'), findsOneWidget);
    expect(find.text('横屏'), findsOneWidget);
    // 横屏组里没有写字（无横屏形态）；竖屏组里没有方向键（横屏专用模块）。
    final landscapeY = tester.getTopLeft(find.text('横屏')).dy;
    expect(find.text('写字'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('写字')).dy,
      lessThan(landscapeY),
    );
    expect(find.text('方向键布局'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('方向键布局')).dy,
      greaterThan(landscapeY),
    );
  });

  testWidgets('点行 = 切该组激活：回调带组朝向与布局 id', (tester) async {
    final calls = <(String, String)>[];
    await _pump(
      tester,
      layouts: _builtinLayouts(),
      onSwitch: (o, id) => calls.add((o, id)),
    );
    await tester.tap(find.text('键盘布局'));
    await tester.pump();
    expect(calls.single, (kRtCanvasOrientLandscape, kRtCanvasTemplateKeyboard.id));
  });

  testWidgets('固定布局无 ⋯；可编辑行各有 ⋯（写字除外）', (tester) async {
    await _pump(tester, layouts: _builtinLayouts(), onSwitch: (_, _) {});
    // 竖屏组：写字(无) + 触控屏(有)；横屏组：方向键/轮盘/键盘/触控屏(有)。
    expect(find.byIcon(Icons.more_horiz), findsNWidgets(5));
  });

  testWidgets('内置行 ⋯ 菜单：画布编辑 + 恢复出厂，无改名/删除', (tester) async {
    await _pump(tester, layouts: _builtinLayouts(), onSwitch: (_, _) {});
    await tester.tap(find.text('键盘布局'));
    await tester.pump();
    // 行点击与 ⋯ 是两个手势目标：直接点 ⋯ 图标。
    await tester.tap(find.byIcon(Icons.more_horiz).at(3));
    await tester.pumpAndSettle();
    expect(find.text('在画布上编辑'), findsOneWidget);
    expect(find.text('恢复出厂摆放'), findsOneWidget);
    expect(find.text('改名'), findsNothing);
    expect(find.text('删除布局'), findsNothing);
  });

  testWidgets('自定义行 ⋯ 菜单：改名 + 删除，无恢复出厂', (tester) async {
    const custom = RtCanvasNamedLayout(
      id: 'custom-1',
      name: '我的布局',
      builtIn: false,
      orientation: kRtCanvasOrientLandscape,
      data: RtCanvasLayout(),
    );
    await _pump(
      tester,
      layouts: RtCanvasLayouts(
        list: [...kRtCanvasBuiltinPresets, custom],
        activeId: kRtCanvasPresetTouchpad,
      ),
      onSwitch: (_, _) {},
    );
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    expect(find.text('改名'), findsOneWidget);
    expect(find.text('删除布局'), findsOneWidget);
    expect(find.text('恢复出厂摆放'), findsNothing);
  });

  testWidgets('应用设置入口（无画布）：菜单无「在画布上编辑」', (tester) async {
    await _pump(
      tester,
      layouts: _builtinLayouts(),
      onSwitch: (_, _) {},
      canEditOnCanvas: false,
    );
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    expect(find.text('在画布上编辑'), findsNothing);
    expect(find.text('恢复出厂摆放'), findsOneWidget);
  });
}
