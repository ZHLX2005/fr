// RT 设置页 widget 测试（布局大卡重构后）：
//   · 设置页能打开、布局区 = 一张大卡（竖屏组在上、横屏组在下）；
//   · 旧的四段顶层入口（布局列表 / 布局管理 / 模块与布局 / 拖拽编辑）已收敛；
//   · 「回车行为」在这里切换并落盘；
//   · 大卡上的动作真的落盘：切激活 / 新建 / 改名 / 删除。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/template/rt_canvas_presets.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart'
    show
        RtCanvasLayouts,
        RtPrefs,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
        kRtCanvasPresetWriter,
        rtCanvasLayoutUsableIn;
import 'package:xiaodouzi_fr/core/remotetype/settings/rt_settings_page.dart';
import 'package:xiaodouzi_fr/core/remotetype/ui/rt_layout_picker.dart';

/// 打开设置页并等首屏（加载 prefs 是异步的）。
Future<void> _openSettings(WidgetTester tester) async {
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
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页渲染布局大卡与输入区，回车行为可切并落盘', (tester) async {
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
    // 大卡双组：竖屏组在上、横屏组在下
    expect(find.text('竖屏'), findsOneWidget);
    expect(find.text('横屏'), findsOneWidget);
    // 组员：写字/方向键/轮盘/键盘各一行；触控屏双朝向 → 两组各一行
    expect(find.text('写字'), findsOneWidget);
    expect(find.text('方向键布局'), findsOneWidget);
    expect(find.text('轮盘布局'), findsOneWidget);
    expect(find.text('键盘布局'), findsOneWidget);
    expect(find.text('触控屏布局'), findsNWidgets(2));
    // 旧的四段顶层入口已收敛：管理进行尾 ⋯，新建是卡下虚线行
    expect(find.text('布局管理'), findsNothing);
    expect(find.text('模块与布局'), findsNothing);
    expect(find.text('在画布上拖拽编辑'), findsNothing);
    expect(find.text('新建自定义布局'), findsOneWidget);
    // 回车行为默认 = 发送
    expect(find.text('发送（普通 Enter）'), findsOneWidget);

    // 切一次 → 变成换行，并落盘
    await tester.tap(find.text('回车行为'));
    await tester.pumpAndSettle();
    expect(find.text('换行（Shift+Enter）'), findsOneWidget);
    expect(await RtPrefs.loadEnterMode(), 'shift_enter');
  });

  testWidgets('布局切换面板：第一层是所有布局的列表，底下附设置入口', (
    tester,
  ) async {
    final layouts = const RtCanvasLayouts(
      list: kRtCanvasBuiltinPresets,
      activeId: kRtCanvasPresetWriter,
      activeIdPortrait: kRtCanvasPresetWriter,
    );
    var settingsOpened = false;

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
                  onPick: (id, groupOrient) {},
                  onOpenSettings: () => settingsOpened = true,
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
    // 第一层 = 所有布局的列表（按朝向分组，两组都列出、都可点）
    expect(find.text('写字'), findsOneWidget);
    expect(find.text('触控屏布局'), findsWidgets);
    expect(find.text('方向键布局'), findsOneWidget);
    expect(find.text('轮盘布局'), findsOneWidget);
    expect(find.text('键盘布局'), findsOneWidget);
    expect(find.text('竖屏布局'), findsOneWidget);
    expect(find.text('横屏布局'), findsOneWidget);
    // 固定死的布局标注不可编辑
    expect(find.text('固定布局'), findsOneWidget);
    // 设置入口附在列表下面
    expect(find.text('远程输入设置'), findsOneWidget);

    // 点设置入口 → 回调触发（面板先关）
    await tester.tap(find.text('远程输入设置'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
  });

  testWidgets('点行切激活并落盘（横屏组点键盘布局 → activeId 变）', (
    tester,
  ) async {
    await _openSettings(tester);
    await tester.tap(find.text('键盘布局'));
    await tester.pumpAndSettle();
    final layouts = await RtPrefs.loadCanvasLayouts();
    expect(layouts.activeId, kRtCanvasPresetKeyboard);
    expect(layouts.list, isNotEmpty);
  });

  testWidgets('新建：选朝向建空画布 → 落盘一条自定义', (tester) async {
    await _openSettings(tester);
    await tester.tap(find.text('新建自定义布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('横屏布局'));
    await tester.pumpAndSettle();
    final layouts = await RtPrefs.loadCanvasLayouts();
    final custom = layouts.list.where((p) => !p.builtIn).toList();
    expect(custom, hasLength(1));
    expect(custom.single.orientation, kRtCanvasOrientLandscape);
    expect(custom.single.data.modules, isEmpty);
  });

  testWidgets('自定义行 ⋯：改名与删除都落盘', (tester) async {
    await _openSettings(tester);
    // 先建一条自定义（横屏空画布 → 两组各一行）。
    await tester.tap(find.text('新建自定义布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('横屏布局'));
    await tester.pumpAndSettle();

    // 改名：行尾 ⋯（最后一行的 ⋯ = 横屏组里的自定义）→ 改名 → 改名对话框
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('改名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我的游戏盘');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    var layouts = await RtPrefs.loadCanvasLayouts();
    expect(
      layouts.list.firstWhere((p) => !p.builtIn).name,
      '我的游戏盘',
    );

    // 删除：⋯ → 删除布局 → 确认
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除布局'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    layouts = await RtPrefs.loadCanvasLayouts();
    expect(layouts.list.where((p) => !p.builtIn), isEmpty);
  });

  testWidgets('组内拖拽排序落盘：竖屏组变、横屏组相对次序不变', (tester) async {
    await _openSettings(tester);
    // 竖屏组第一行（写字）的把手向下拖过触控屏一行
    await tester.drag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    final layouts = await RtPrefs.loadCanvasLayouts();
    final portraitIds = layouts.list
        .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p))
        .map((p) => p.id)
        .toList();
    expect(portraitIds, [kRtCanvasPresetTouchpad, kRtCanvasPresetWriter]);
    // 排序是全局一份顺序：被写字跨过的双朝向行（触控屏）在横屏组挪到最前；
    // 排序是全局一份顺序：被写字跨过的双朝向行（触控屏）在横屏组挪到最前；
    // 横屏专属行（双朝向除外）的相对次序不变（语义见 docs/rt-settings-layouts-card-定稿说明.md）
    final landscapeIds = layouts.list
        .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p))
        .map((p) => p.id)
        .toList();
    expect(landscapeIds.first, kRtCanvasPresetTouchpad);
    bool exclusiveL(p) =>
        rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p) &&
        !rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p);
    final exclusiveIds = layouts.list
        .where(exclusiveL)
        .map((p) => p.id)
        .toList();
    final expectedExclusive = kRtCanvasBuiltinPresets
        .where(exclusiveL)
        .map((p) => p.id)
        .toList();
    expect(exclusiveIds, expectedExclusive);
  });

  testWidgets('内置行 ⋯：恢复出厂摆放走确认，布局保留且数据回出厂', (tester) async {
    await _openSettings(tester);
    await tester.tap(find.byIcon(Icons.more_horiz).first); // 竖屏组触控屏行
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复出厂摆放'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    final layouts = await RtPrefs.loadCanvasLayouts();
    final touchpad = layouts.list.firstWhere(
      (p) => p.id == kRtCanvasPresetTouchpad,
    );
    final factory = rtBuiltinPresetOf(kRtCanvasPresetTouchpad)!;
    expect(touchpad.data.modules.length, factory.data.modules.length);
  });
}
