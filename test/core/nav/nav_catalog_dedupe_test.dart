// nav 目录去重回归：别名 slug 指向同一 demo 实例时，只能生成一个钉选单元。
//
// 背景（2026-10-28）：Rive demo 把同一实例注册了 4 个 slug（主 slug + 3 个
// 历史别名 rive-pendulum / rive-data-bind / demo-lab）。nav_catalog 原先逐条
// 遍历 demoRegistry.getAll()，于是同一实例生成 4 个 **同 id** 的 NavEntry ——
// 设置钉选区与底栏候选里出现四张一样的 Rive 图标格子。
// Lab 列表早就有实例去重（lab_page.dart），nav 目录此前漏了。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/nav/nav_catalog.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';

void main() {
  // demo 注册在 bootstrapLab 里完成（app 启动时调用）；不 bootstrap 则注册表为空，
  // 去重断言会空转通过。
  setUpAll(bootstrapLab);

  test('nav 目录中同一 demo 实例只出现一次（别名不重复生成条目）', () {
    final entries = buildNavCatalog();

    // 所有条目 id 唯一——同 id 重复即为别名漏去重。
    final ids = entries.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length,
        reason: '存在重复 id（别名未去重）: '
            '${ids.where((id) => ids.where((x) => x == id).length > 1).toSet()}');

    // 同一 title 不应出现多张卡片（Rive demo 的四个 slug 指向同一实例）。
    final titles = entries.map((e) => e.title).toList();
    for (final t in titles.toSet()) {
      expect(titles.where((x) => x == t).length, 1,
          reason: '标题「$t」重复出现（同一 demo 实例的别名未去重）');
    }
  });

  test('Rive demo 的四个别名 slug 只生成一个钉选条目', () {
    final entries = buildNavCatalog();
    final riveEntries =
        entries.where((e) => e.title.toLowerCase().contains('rive')).toList();
    expect(riveEntries.length, 1,
        reason: 'Rive 出现 ${riveEntries.length} 个钉选条目（应为 1）');
  });
}
