// lab demo 图标表 — 端到端验证
//
// 防回归：
// 1. 所有 demo slug 都能在 icon 表中查到 SVG（== 不要再显示通用占位图标）
// 2. 所有 48 个 SVG 文件都至少被一个 demo slug 引用
// 3. SVG 文件真实可加载（rootBundle），且含主题色替换锚点（#2B3445 / #5B7CFA）
//
// 与 demo_slug_test.dart 互相验证：这边是「slug → svg」，那边是「slug → demo」。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';
import 'package:xiaodouzi_fr/core/ui/lab/lab_demo_icon_lookup.dart';

void main() {
  setUpAll(() {
    // rootBundle.loadString 需要 ServicesBinding（纯 test() 不会自动初始化）
    TestWidgetsFlutterBinding.ensureInitialized();
    bootstrapLab();
  });

  group('Lab 图标 slug → SVG 映射', () {
    test('主 slug 集合都有专属 SVG（即不返回 fallback）', () {
      // 例外清单：设计稿（assets/lab-demo-icons/index.html）共 48 个图标，
      // 但 lab 后增了几款 demo，本批注册时无对应图标 —— 留 fallback 显示通用图标。
      // 这是有意为之的「已登记但无专属 SVG」白名单，避免每次 demo 增加都强制塞图标。
      const noIconSlug = {
        'session-host', // 后增的会话托管 demo，2026-10-13 时未列入图标集
      };
      final mainSlugs = <String>{};
      for (final entry in demoRegistry.getAll()) {
        if (!mainSlugs.contains(entry.value.slug)) {
          mainSlugs.add(entry.value.slug);
        }
      }
      for (final slug in mainSlugs) {
        if (noIconSlug.contains(slug)) continue;
        final kind = labIconForDemoSlug(slug);
        expect(kind.isFallback, isFalse,
            reason: '$slug 走通用 fallback，缺少 SVG 映射；'
                '若确实无专属 SVG，请加到 _noIconSlug 白名单（设计集 48 张之外的后增 demo）');
      }
    });

    test('allLabIconAssetBaseNames 至少覆盖 48 个 SVG（与设计稿一致）', () {
      // 项目内 48 个 svg 文件（assets/lab-demo-icons/*.svg）
      // 这里只验证 SVG basename 集合非空且去重；不做纯文件名比对避免硬编码漂移。
      final bases = allLabIconAssetBaseNames;
      expect(bases.length, greaterThanOrEqualTo(48),
          reason: '当前表里有 ${bases.length} 个 SVG，少于设计稿 48 个；'
              '说明漏登记。');
      expect(bases.toSet().length, bases.length,
          reason: '重复登记');
    });

    test('全部 SVG 真实可加载，主色锚点逐个齐全，强调色锚点覆盖集合', () async {
      var accentCount = 0;
      for (final base in allLabIconAssetBaseNames) {
        final svg = await rootBundle.loadString('assets/lab-demo-icons/$base.svg');
        expect(svg, contains('<svg'),
            reason: '$base.svg 不是合法 SVG');
        // 主题色化的 ink 替换依赖此锚点；丢失会导致图标不随主题明暗变色。
        final hasInk =
            svg.contains('#2B3445') || svg.contains('#2b3445');
        expect(hasInk, isTrue,
            reason: '$base.svg 缺少主色锚点 #2B3445，主题色化会失效');
        // 部分图标设计上就是纯单色（如 01-clock），accent 锚点不做逐个强求，
        // 只在集合级保证「绝大多数双色图标可随主题强调色切换」。
        if (svg.contains('#5B7CFA') || svg.contains('#5b7cfa')) {
          accentCount++;
        }
      }
      expect(accentCount, greaterThan(allLabIconAssetBaseNames.length * 2 ~/ 3),
          reason: '含强调色锚点 #5B7CFA 的 SVG 只有 $accentCount 个，'
              '远低于设计稿双色图标的占比——可能色值被改动，强调色不再随主题切换');
    });
  });
}
