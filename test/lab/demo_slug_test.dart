// demo slug 端到端验证：kDemoSlugs + demoRegistry 双索引 + LabDemoHandler。
// 防止 fr://lab/demo/clock 跳不到对应 demo 的回归。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';

void main() {
  setUpAll(bootstrapLab);

  group('demo slug 双索引', () {
    test('demoRegistry.get(slug) 命中（clock）', () {
      final demo = demoRegistry.get('clock');
      expect(demo, isNotNull);
      expect(demo!.title, '时钟');
    });

    test('getBySlug / getByTitle 分离', () {
      expect(demoRegistry.getBySlug('clock')?.title, '时钟');
      expect(demoRegistry.getByTitle('时钟')?.slug, 'clock');
    });

    test('DemoPage.slug 默认查 kDemoSlugs', () {
      final clock = demoRegistry.getByTitle('时钟')!;
      expect(clock.slug, 'clock');
      final calendar = demoRegistry.getByTitle('日历待办')!;
      expect(calendar.slug, 'calendar');
    });

    test('getAll() 的 key 是 slug（非 title）', () {
      final keys = demoRegistry.getAll().map((e) => e.key).toSet();
      expect(keys, contains('clock'));
      expect(keys, contains('calendar'));
      expect(keys, contains('overlay'));
      // key 不应是中文 title
      expect(keys.any((k) => k == '时钟'), isFalse,
          reason: 'getAll key 必须是 slug 不能是中文 title');
    });

    test('37 个 demo 全部有英文 slug（无中文残留）', () {
      final all = demoRegistry.getAll();
      expect(all.length, greaterThanOrEqualTo(37));
      for (final entry in all) {
        final slug = entry.key;
        // slug 必须纯 ASCII（fr://lab/demo/{slug} 不能含中文，否则 FrUri safeDecode 兜底但不优雅）
        expect(slug.codeUnits.every((c) => c < 128), isTrue,
            reason: 'slug "$slug" 含非 ASCII 字符，请检查 kDemoSlugs 或 demo.title: ${entry.value.title}');
      }
    });
  });
}
