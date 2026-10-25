// 游戏中心目录防漂移（派生版）。
//
// 目录是 demoRegistry + kGameMeta 的纯派生（见 buildGameCenterCatalog），
// 「漏登记 catalog」这类漂移已不存在；要防的只剩两类：
//   ① 注册 game 没进 kGameMeta —— 目录 categories/mode 失真 + 卡片灰兜底封面；
//   ② 派生 JSON 不确定 / 形状漂移 —— compare-then-write 的幂等被破坏、ve 解析挂。
// 历史：2026-09-24 数独漏登记、2026-10-25 跳棋/象棋因「忘重发 KV」缺席 ve 端。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/game_kit/game_center_catalog.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/game_center/const_game_center.dart';

/// 与 GameCenterPage.initState 相同的取数逻辑（按注册顺序、别名 slug 去重）。
List<DemoPage> registeredGames() {
  final seen = <DemoPage>{};
  return demoRegistry
      .getAll()
      .filterByType(DemoType.game)
      .map((e) => e.value)
      .where(seen.add)
      .toList();
}

void main() {
  setUpAll(bootstrapLab);

  group('game-center 目录派生防漂移', () {
    test('每个注册 game 都在 kGameMeta 有登记（漏登记 = 灰兜底封面 + 目录失真）', () {
      for (final d in registeredGames()) {
        expect(
          gameMetaOf(d.slug),
          isNot(same(kFallbackGameMeta)),
          reason: 'game "${d.slug}" 缺 GameMeta 登记，'
              '请在 const_game_center.dart 的 kGameMeta 补一条',
        );
      }
    });

    test('派生确定性：同一输入两次派生 JSON 逐字节一致（compare-then-write 幂等前提）', () {
      final games = registeredGames();
      expect(
        gameCenterCatalogJson(buildGameCenterCatalog(games)),
        gameCenterCatalogJson(buildGameCenterCatalog(games)),
      );
    });

    test('派生条目字段与 demo / kGameMeta 一致', () {
      for (final d in registeredGames()) {
        final entries = buildGameCenterCatalog([d]);
        expect(entries, hasLength(1));
        final e = entries.single;
        expect(e.slug, d.slug);
        expect(e.title, d.title);
        expect(e.description, d.description);
        expect(e.categories, unorderedEquals(gameMetaOf(d.slug).categories));
        expect(e.mode, gameMetaOf(d.slug).mode);
        expect(e.isOnline, gameMetaOf(d.slug).isOnline);
      }
    });

    test('slug 纯 ASCII 小写（= ve 侧 skinId，必须稳定）', () {
      for (final e in buildGameCenterCatalog(registeredGames())) {
        expect(
          e.slug,
          matches(RegExp(r'^[a-z0-9][a-z0-9-]*$')),
          reason: 'slug "${e.slug}" 含非法字符（skinId 须稳定 ASCII）',
        );
      }
    });

    test('KV value 形状：每条都带 ve 端消费的六个字段', () {
      final decoded = jsonDecode(
        gameCenterCatalogJson(buildGameCenterCatalog(registeredGames())),
      ) as List<dynamic>;
      expect(decoded, isNotEmpty);
      for (final e in decoded) {
        expect(e, isA<Map<String, dynamic>>());
        final m = e! as Map<String, dynamic>;
        for (final k in [
          'slug',
          'title',
          'description',
          'mode',
          'categories',
          'isOnline',
        ]) {
          expect(m.containsKey(k), isTrue, reason: '目录条目缺字段 $k');
        }
      }
    });
  });
}
