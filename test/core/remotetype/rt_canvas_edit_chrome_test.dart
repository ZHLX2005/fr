// 画布编辑态 chrome 的摆放规则测试（重构后新增）：
//   · 竖屏：收纳控件在头部（顶部），点开显示功能清单；
//   · 横屏：收纳控件在右侧（不放头部），点开显示右侧竖排控制列表。
//
// 画布本身不需要真会话（session 可空），这里只验 chrome 的位置与展开。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_view.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart';

Widget _canvas({
  required bool editMode,
  required String orientation,
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
              shortcuts: const [],
              firingId: null,
              activeLayout: const RtCanvasLayout(),
              activeId: 'custom-1',
              composerModule: const SizedBox.shrink(),
              editMode: editMode,
              onLayoutChanged: (_) {},
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
  testWidgets('竖屏：收纳控件在头部（顶部），点开展开功能清单', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _canvas(editMode: true, orientation: kRtCanvasOrientPortrait),
    );
    await tester.pumpAndSettle();

    // 默认收纳：只剩一颗「编辑工具」chip
    expect(find.text('编辑工具'), findsOneWidget);
    expect(find.text('编辑快捷键'), findsNothing);

    final chip = tester.getCenter(find.text('编辑工具'));
    expect(chip.dy, lessThan(800 * 0.2)); // 靠顶部 = 头部

    // 点开 → 功能清单出现（模块 chip + 编辑快捷键 + 完成）
    await tester.tap(find.text('编辑工具'));
    await tester.pumpAndSettle();
    expect(find.text('编辑快捷键'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    // 清单仍落在头部一带
    final shortcuts = tester.getCenter(find.text('编辑快捷键'));
    expect(shortcuts.dy, lessThan(800 * 0.2));
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
}
