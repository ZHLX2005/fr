// demo slug 端到端验证：DemoPage.slug 必须纯 ASCII，demoRegistry 双索引 + LabDemoHandler。
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

    test('DemoPage.slug 与 kDemoSlugs 表解耦，子类自带', () {
      // slug 在子类文件内声明（不再依赖 lab_container.dart 全局表）。
      // 验证：直接读 DemoPage.slug 字段值（不通过 map 查询）。
      final clock = demoRegistry.getByTitle('时钟')!;
      expect(clock.slug, 'clock');
      final calendar = demoRegistry.getByTitle('日历待办')!;
      expect(calendar.slug, 'calendar');
      // 新合并的统一 demo 走 rive-demo slug，旧的 3 个 slug（rive-pendulum /
      // rive-data-bind / demo-lab）以 register(demo, key: alias) 别名形式注册。
      final rive = demoRegistry.getBySlug('rive-demo')!;
      expect(rive.title, 'Rive 演示');
      expect(demoRegistry.getBySlug('rive-pendulum'), same(rive));
      expect(demoRegistry.getBySlug('demo-lab'), same(rive));
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

    test('全部 demo 的 slug 纯 ASCII（无中文残留）', () {
      final all = demoRegistry.getAll();
      expect(all.length, greaterThanOrEqualTo(35));
      for (final entry in all) {
        final slug = entry.key;
        // slug 必须纯 ASCII（fr://lab/demo/{slug} 不能含中文，否则 FrUri safeDecode 兜底但不优雅）
        expect(slug.codeUnits.every((c) => c < 128), isTrue,
            reason: 'slug "$slug" 含非 ASCII 字符，请检查 demo.slug 字段: ${entry.value.title}');
        // DemoPage.slug 与注册 key 一致（除非别名）
        // （别名情况下 entry.key 是 key override，entry.value.slug 是原始 slug，二者可不同，
        //   所以此处不强制相等）
      }
    });
  });
}