import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/nav/nav_pins_notifier.dart';
import 'package:xiaodouzi_fr/screens/settings/app_settings_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppSettingsPage()),
      ),
    );
    await container.read(navPinsProvider.notifier).setPins([
      'core-profile',
      'core-time',
      'core-lab',
    ]);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('设置页正常渲染（无渲染异常）', (tester) async {
    final container = await pump(tester);
    addTearDown(container.dispose);

    expect(tester.takeException(), isNull);
    expect(find.text('个人'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('实验室'), findsOneWidget);
  });

  testWidgets('拖动中垃圾桶浮现，拖入垃圾桶删除对应格', (tester) async {
    final container = await pump(tester);
    addTearDown(container.dispose);
    expect(container.read(navPinsProvider).pinIds, [
      'core-profile',
      'core-time',
      'core-lab',
    ]);

    // 垃圾桶默认不可见
    expect(find.text('拖到这里删除'), findsNothing);

    // 长按「Time」格 200ms 触发拖动
    final cell = find.text('Time');
    final cellCenter = tester.getCenter(cell);
    final gesture = await tester.startGesture(cellCenter);
    await tester.pump(const Duration(milliseconds: 350)); // 过长按阈值
    await gesture.moveBy(const Offset(0, 200)); // 明确进入拖拽态
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 拖动中垃圾桶可见
    expect(find.text('拖到这里删除'), findsOneWidget);

    // 回拖到垃圾桶中心松手
    final trashCenter = tester.getCenter(find.text('拖到这里删除'));
    await gesture.moveTo(trashCenter);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(navPinsProvider).pinIds, [
      'core-profile',
      'core-lab',
    ]);
    // 松手后垃圾桶收回
    expect(find.text('拖到这里删除'), findsNothing);
  });

  testWidgets('网格内拖动换位（不受垃圾桶通路影响）', (tester) async {
    final container = await pump(tester);
    addTearDown(container.dispose);

    // 长按「Time」格，小幅拖到第一格位置（网格内换位，不触垃圾桶）
    final cell = find.text('Time');
    final cellCenter = tester.getCenter(cell);
    final gesture = await tester.startGesture(cellCenter);
    await tester.pump(const Duration(milliseconds: 350));
    // 第一格在左边一格列宽处（4 列网格，测试视口 800 宽 → 格宽约 190）
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(navPinsProvider).pinIds.first, 'core-time');
    // 换位路径没碰垃圾桶，列表长度不变
    expect(container.read(navPinsProvider).pinIds.length, 3);
  });
}
