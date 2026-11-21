// fr #41 视觉探针：把设置页与 Lab 网格渲染成 golden PNG（--update-goldens 生成），
// 人工目检验收三项样式修复的真实效果（代码在位 ≠ 视觉正确）。
//
// 产出落在 ../../temp/goldens/style39/（temp/ 已 gitignore，不入库）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/nav/nav_pins_notifier.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/demo_grid/demo_reveal_grid.dart';
import 'package:xiaodouzi_fr/screens/settings/app_settings_page.dart';

void main() {
  setUpAll(() async {
    // 测试默认 Ahem 字体会把中文渲染成方块；加载系统微软雅黑保证
    // golden 与真机视觉一致。Windows-only（本项目冒烟跑在 Windows 上）。
    final fontFile = File(r'C:\Windows\Fonts\msyh.ttc');
    if (!fontFile.existsSync()) return;
    final bytes = fontFile.readAsBytesSync();
    final loader = FontLoader('VisualSmokeFont')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  // 手机视口（原始问题截图的形态：窄屏，trailing 空间紧张）
  void phoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('golden：设置页（底栏容量卡片）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    phoneView(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6B7F82),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            fontFamily: 'VisualSmokeFont',
          ),
          home: const AppSettingsPage(),
        ),
      ),
    );
    await container.read(navPinsProvider.notifier).setPins([
      'core-profile',
      'core-games',
      'core-lab',
    ]);
    await tester.pumpAndSettle();

    // 滚到通用卡片（底栏容量在页面底部）
    await tester.scrollUntilVisible(
      find.text('底栏容量（含 ⋯）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppSettingsPage),
      matchesGoldenFile('../../temp/goldens/style39/settings.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('golden：Lab 网格（卡片密度 + 课程表/番茄钟 SVG）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    phoneView(tester);
    bootstrapLab();
    final demos = demoRegistry.getAll();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6B7F82),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          fontFamily: 'VisualSmokeFont',
        ),
        home: Scaffold(
          body: DemoScrollRevealGrid(
            demos: demos,
            controller: controller,
            onDemoTap: (_) {},
            physics: const ClampingScrollPhysics(),
          ),
        ),
      ),
    );
    // RevealItem 入场动画 1200ms：跳到动画末态
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DemoScrollRevealGrid),
      matchesGoldenFile('../../temp/goldens/style39/lab_grid.png'),
    );
  }, skip: !Platform.isWindows);
}
