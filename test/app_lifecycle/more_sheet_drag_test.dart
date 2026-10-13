// 「更多」弹窗拖拽排序回归。
// test/ 被 gitignore 拦新增，收录走 git add -f。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/app_lifecycle/press_bounce_curve.dart';
import 'package:xiaodouzi_fr/core/nav/nav_pins_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavPinsNotifier.setPins 重组 → overflowIds', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('visible 段保留 / overflow 段重排', () async {
      // 纯核心入口 fixture（AI 拆分组已从 catalog 移除，ai-* id 会被
      // sanitize 丢弃）：5 元素条 → visible 前 3 / overflow 后 2
      await container.read(navPinsProvider.notifier).setPins([
        'core-time',
        'core-lab',
        'core-games',
        'core-profile',
        'core-theme',
      ]);
      final pins0 = container.read(navPinsProvider);
      expect(pins0.visibleIds, ['core-time', 'core-lab', 'core-games']);
      expect(pins0.overflowIds, ['core-profile', 'core-theme']);

      // 模拟更多弹窗 onReorder：保留 visible、重排 overflow
      await container.read(navPinsProvider.notifier).setPins([
        ...pins0.visibleIds,
        'core-theme',
        'core-profile',
      ]);

      final pins1 = container.read(navPinsProvider);
      expect(pins1.visibleIds, ['core-time', 'core-lab', 'core-games'],
          reason: 'visible 段顺序保留不被乱动');
      expect(pins1.overflowIds, ['core-theme', 'core-profile'],
          reason: 'overflow 段新顺序生效');
    });

    test('sanitize 兜底：传空或全未知 → 回退出厂默认', () async {
      await container.read(navPinsProvider.notifier).setPins([]);
      expect(container.read(navPinsProvider).pinIds, kDefaultNavPins);
    });
  });

  group('PressBounceCurve 关键节点', () {
    test('t=0 → 1.0（原大小）', () {
      expect(const PressBounceCurve().transformInternal(0), 1.0);
    });
    test('t=0.7 → 1.08（峰值）', () {
      expect(const PressBounceCurve().transformInternal(0.7), closeTo(1.08, 1e-9));
    });
    test('t=1 → 1.0（收回）', () {
      expect(const PressBounceCurve().transformInternal(1), 1.0);
    });
    test('t=0.35 → 1.04（前半段 8% 线性叠加）', () {
      // 1.0 + (0.35/0.7) * 0.08 = 1.04
      expect(const PressBounceCurve().transformInternal(0.35), closeTo(1.04, 1e-9));
    });
  });
}
