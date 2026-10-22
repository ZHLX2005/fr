// RT 设置页 widget 测试（重构后新增）：
//   · 设置页能打开、渲染出布局与输入两区；
//   · 「回车行为」在这里切换并落盘（原先是写字页工具行上的两颗小按钮）；
//   · 布局切换面板只列当前朝向可用的布局，固定布局标「固定布局」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/template/rt_canvas_presets.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart';
import 'package:xiaodouzi_fr/core/remotetype/settings/rt_settings_page.dart';
import 'package:xiaodouzi_fr/core/remotetype/ui/rt_layout_picker.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页渲染布局与输入两区，回车行为可切并落盘', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRtSettingsPage(context),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();

    expect(find.text('远程输入设置'), findsOneWidget);
    expect(find.text('布局'), findsOneWidget);
    expect(find.text('输入'), findsOneWidget);
    // 回车行为默认 = 发送
    expect(find.text('发送（普通 Enter）'), findsOneWidget);

    // 切一次 → 变成换行，并落盘
    await tester.tap(find.text('回车行为'));
    await tester.pumpAndSettle();
    expect(find.text('换行（Shift+Enter）'), findsOneWidget);
    expect(await RtPrefs.loadEnterMode(), 'shift_enter');
  });

  testWidgets('布局切换面板：只列可用布局，固定布局标注不可编辑', (tester) async {
    final layouts = const RtCanvasLayouts(
      list: kRtCanvasBuiltinPresets,
      activeId: kRtCanvasPresetWriter,
      activeIdPortrait: kRtCanvasPresetWriter,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRtLayoutPicker(
                  context,
                  layouts: layouts,
                  orientation: kRtCanvasOrientPortrait,
                  activeId: kRtCanvasPresetWriter,
                  onPick: (_) {},
                ),
                child: const Text('打开面板'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();

    expect(find.text('切换布局'), findsOneWidget);
    expect(find.text('写字'), findsOneWidget);
    // 竖屏可用：写字 + 触控屏（双朝向）；游戏/键盘锁横屏 → 不列
    expect(find.text('触控屏布局'), findsOneWidget);
    expect(find.text('游戏布局'), findsNothing);
    expect(find.text('键盘布局'), findsNothing);
    // 固定死的布局标注不可编辑
    expect(find.text('固定布局'), findsOneWidget);
  });
}
