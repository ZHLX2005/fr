// NavPinsNotifier.removePin 边界测试：
//   · 已存在 id → 删除后 pinIds 少 1 个；
//   · 不存在 id → pinIds 不变（幂等）；
//   · 只剩 1 条时 → 不删除（保留底栏至少 1 个入口）。
//
// 走 NotifierProvider 直接构造 state，绕开 SharedPreferences（hydrate 在
// main() 前调用，与单测隔离）。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/nav/nav_pins_notifier.dart';

void main() {
  setUp(() {
    // 隔离干净 prefs，避免单测间串数据。
    SharedPreferences.setMockInitialValues({});
  });

  group('removePin', () {
    test('删除已存在的 id 后 pinIds 少 1 条', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(navPinsProvider.notifier);

      await notifier.setPins(['core-profile', 'core-time', 'core-lab']);
      expect(container.read(navPinsProvider).pinIds.length, 3);

      await notifier.removePin('core-time');
      final next = container.read(navPinsProvider).pinIds;
      expect(next, ['core-profile', 'core-lab']);
      expect(next.contains('core-time'), isFalse);
    });

    test('删除不存在的 id 时 pinIds 不变（幂等）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(navPinsProvider.notifier);

      await notifier.setPins(['core-profile', 'core-time', 'core-lab']);
      await notifier.removePin('nonexistent-id');
      expect(
        container.read(navPinsProvider).pinIds,
        ['core-profile', 'core-time', 'core-lab'],
      );
    });

    test('pinIds 只剩 1 条时拒绝删除（保留底栏至少 1 入口）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(navPinsProvider.notifier);

      await notifier.setPins(['core-profile']);
      await notifier.removePin('core-profile');
      expect(container.read(navPinsProvider).pinIds, ['core-profile']);
    });
  });
}