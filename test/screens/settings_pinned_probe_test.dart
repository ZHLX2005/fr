import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/nav/nav_pins_notifier.dart';
import 'package:xiaodouzi_fr/screens/settings/app_settings_page.dart';
import 'package:xiaodouzi_fr/screens/settings/const_settings.dart';

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

  /// 长按「Time」格 200ms 触发拖动（阈值见 kSettingsDragLongPressDelay）。
  Future<TestGesture> startDraggingTime(WidgetTester tester) async {
    final cell = find.text('Time');
    final gesture = await tester.startGesture(tester.getCenter(cell));
    await tester.pump(const Duration(milliseconds: 350)); // 过长按阈值
    await gesture.moveBy(const Offset(0, 200)); // 明确进入拖拽态
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return gesture;
  }

  testWidgets('设置页正常渲染（无渲染异常）', (tester) async {
    final container = await pump(tester);
    addTearDown(container.dispose);

    expect(tester.takeException(), isNull);
    expect(find.text('个人'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('实验室'), findsOneWidget);
  });

  testWidgets('垃圾桶是横向宽扁投放条（命中区大于旧 48px 圆钮）', (tester) async {
    final container = await pump(tester);
    addTearDown(container.dispose);

    final gesture = await startDraggingTime(tester);
    addTearDown(gesture.up);

    final bar = find.byKey(kSettingsTrashBarKey);
    expect(bar, findsOneWidget);

    final size = tester.getSize(bar);
    // 横向：宽 > 高（不再是 48×48 圆钮）
    expect(size.width, greaterThan(size.height));
    // 命中区明显大于旧版 48px 圆钮
    expect(size.width, greaterThan(48));
    expect(size.height, greaterThanOrEqualTo(48));

    // 带文案提示，别只靠图标猜
    expect(find.text('拖到这里删除'), findsOneWidget);
    // 图标仍在
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('拖动中屏幕底部垃圾桶浮现，拖入删除对应格', (tester) async {
    final container = await pump(tester);
    addTearDown(container.dispose);
    expect(container.read(navPinsProvider).pinIds, [
      'core-profile',
      'core-time',
      'core-lab',
    ]);

    // 垃圾桶默认不可见
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

    final gesture = await startDraggingTime(tester);

    // 拖动中屏幕底部垃圾桶投放条可见
    final trashIcon = find.byIcon(Icons.delete_outline_rounded);
    expect(trashIcon, findsOneWidget);
    final bar = find.byKey(kSettingsTrashBarKey);
    // 位置在屏幕底部（底边超过视口高度的 4/5）
    expect(tester.getBottomRight(bar).dy, greaterThan(600 * 0.8));

    // 拖到垃圾桶投放条中心 → 悬停染错色
    await gesture.moveTo(tester.getCenter(bar));
    await tester.pump(const Duration(milliseconds: 200));
    final hovered = tester.widget<AnimatedContainer>(bar).decoration! as BoxDecoration;
    final cs = Theme.of(tester.element(bar)).colorScheme;
    expect(hovered.color, cs.errorContainer);

    // 松手
    await gesture.up();
    await tester.pumpAndSettle();

    expect(container.read(navPinsProvider).pinIds, [
      'core-profile',
      'core-lab',
    ]);
    // 松手后垃圾桶收回
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
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
