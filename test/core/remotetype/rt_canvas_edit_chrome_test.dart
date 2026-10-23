// 画布编辑态 chrome 的摆放规则测试：
//   · 竖屏：收纳 chip 默认在右上（头部一带），点开为右上圆角弹窗功能清单；
//   · 横屏：收纳 chip 在右缘，点开显示右侧竖排控制列表。
//
// 画布本身不需要真会话（session 可空），这里只验 chrome 的位置与展开。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_view.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart';

Widget _canvas({
  required bool editMode,
  required String orientation,
  List<RtShortcutItem> shortcuts = const [],
  RtCanvasLayout activeLayout = const RtCanvasLayout(),
  ValueChanged<RtCanvasLayout>? onLayoutChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          RtCanvasView(
              session: null,
              connected: true,
              sensitivity: 1,
              onSensitivityChanged: (_) {},
              textController: TextEditingController(),
              shortcuts: shortcuts,
              firingId: null,
              activeLayout: activeLayout,
              activeId: 'custom-1',
              composerModule: const SizedBox.shrink(),
              editMode: editMode,
              onLayoutChanged: onLayoutChanged ?? (_) {},
              onDirection: (_) {},
              onVpadKey: ({
                String? button,
                bool pressed = false,
                String? trigger,
              }) {},
              onStickAxis: (_, _) {},
              onKbChord: (_) {},
              onEditModeChanged: (_) {},
              onFire: (_) async {},
              onEditShortcuts: () {},
              onNotify: (_) {},
            ),
          ],
        ),
      ),
  );
}

void main() {
  testWidgets('竖屏：收纳 chip 默认在右上，点开为右上圆角弹窗功能清单', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _canvas(editMode: true, orientation: kRtCanvasOrientPortrait),
    );
    await tester.pumpAndSettle();

    // 默认收纳：只剩一颗「编辑工具」chip，默认位右上（头部一带）
    expect(find.text('编辑工具'), findsOneWidget);
    expect(find.text('编辑快捷键'), findsNothing);

    final chip = tester.getCenter(find.text('编辑工具'));
    expect(chip.dy, lessThan(800 * 0.2));
    expect(chip.dx, greaterThan(400 * 0.7));

    // 点开 → 右上弹窗功能清单（模块行 + 编辑快捷键 + 完成）
    await tester.tap(find.text('编辑工具'));
    await tester.pumpAndSettle();
    expect(find.text('编辑快捷键'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    // 弹窗右挂（不横贯整屏）：清单起点在屏幕右半区
    final shortcuts = tester.getTopLeft(find.text('编辑快捷键'));
    expect(shortcuts.dx, greaterThan(400 * 0.4));
  });

  testWidgets('横屏：收纳控件在右侧（不在头部），点开显示右侧竖排控制列表', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _canvas(editMode: true, orientation: kRtCanvasOrientLandscape),
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑工具'), findsOneWidget);
    // 收纳控件在右缘，不在头部
    final chip = tester.getCenter(find.text('编辑工具'));
    expect(chip.dx, greaterThan(800 * 0.7));
    expect(chip.dy, lessThanOrEqualTo(400 * 0.5));

    // 点开 → 右侧竖排控制列表（模块行 + 编辑快捷键 + 完成）
    await tester.tap(find.text('编辑工具'));
    await tester.pumpAndSettle();
    expect(find.text('编辑快捷键'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    final shortcuts = tester.getCenter(find.text('编辑快捷键'));
    expect(shortcuts.dx, greaterThan(800 * 0.7));
  });

  testWidgets('快捷键按钮：默认全不显示，面板逐键收录，总开关压整区', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var layout = const RtCanvasLayout();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setS) => _canvas(
          editMode: true,
          orientation: kRtCanvasOrientPortrait,
          shortcuts: [
            RtShortcutItem.single(id: 'sc-a', label: '复制', keys: ['ctrl', 'c']),
            RtShortcutItem.single(id: 'sc-b', label: '粘贴', keys: ['ctrl', 'v']),
          ],
          activeLayout: layout,
          onLayoutChanged: (l) {
            layout = l;
            setS(() {});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 编辑态默认：未收录的键连幽灵都不出（收录入口在面板）
    expect(find.text('复制'), findsNothing);
    expect(find.text('粘贴'), findsNothing);

    // 打开面板：快捷键按钮区在，逐键行列出（画布仍无按钮）
    await tester.tap(find.text('编辑工具'));
    await tester.pumpAndSettle();
    expect(find.text('快捷键按钮'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget); // 仅面板行

    // 点「复制」行 = 收录：画布出现按钮（面板行 + 画布 = 2 处）
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(layout.buttons['sc-a']?.v ?? false, isTrue);
    expect(find.text('复制'), findsNWidgets(2));
    expect(find.text('粘贴'), findsOneWidget); // 未收录仍只有面板行

    // 总开关关：整区压掉（画布按钮消失、逐键行收起）
    await tester.tap(find.text('快捷键按钮'));
    await tester.pumpAndSettle();
    expect(layout.hideShortcuts, isTrue);
    expect(find.text('复制'), findsNothing);

    // 总开关再开：已收录的按钮原样回来
    await tester.tap(find.text('快捷键按钮'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNWidgets(2));
    expect(find.text('粘贴'), findsOneWidget);
  });

  testWidgets('快捷键按钮：使用态只渲染已收录且开启的键', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const layout = RtCanvasLayout(
      buttons: {
        'sc-a': RtCanvasButtonPos(x: 0.5, y: 0.5, v: true),
        'sc-b': RtCanvasButtonPos(x: 0.7, y: 0.7, v: false),
      },
    );
    await tester.pumpWidget(
      _canvas(
        editMode: false,
        orientation: kRtCanvasOrientPortrait,
        shortcuts: [
          RtShortcutItem.single(id: 'sc-a', label: '复制', keys: ['ctrl', 'c']),
          RtShortcutItem.single(id: 'sc-b', label: '粘贴', keys: ['ctrl', 'v']),
        ],
        activeLayout: layout,
      ),
    );
    await tester.pumpAndSettle();

    // 已收录且 v=true 的显示；v=false / 未收录的都不出现
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsNothing);
  });
}
