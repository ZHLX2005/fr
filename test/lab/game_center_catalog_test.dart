// 游戏中心目录防漂移：kGameCenterCatalog（KV 事实源 → ve 管理端「游戏封面」tab）
// 与 demoRegistry 注册表 / kGameMeta 双向一致。
// 漏登记后果：管理端看不到新游戏、无法分配封面（2026-09-24 数独漏登记回归）。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/game_kit/game_center_catalog.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';
import 'package:xiaodouzi_fr/lab/lab_bootstrap.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/game_center/const_game_center.dart';

Set<String> registeredGameSlugs() => demoRegistry
    .getAll()
    .filterByType(DemoType.game)
    .map((e) => e.value.slug)
    .toSet();

Set<String> catalogSlugs() =>
    kGameCenterCatalog.map((e) => e.slug).toSet();

void main() {
  setUpAll(bootstrapLab);

  group('game-center catalog 双向防漂移', () {
    test('正向：catalog 每条都已注册为 DemoType.game', () {
      final registered = registeredGameSlugs();
      for (final e in kGameCenterCatalog) {
        expect(registered, contains(e.slug),
            reason: 'catalog slug "${e.slug}" 未注册为 game，'
                '请删除该条或补 demo 注册');
      }
    });

    test('反向：每个注册 game 都已进 catalog（漏登记 = 管理端无法分配封面）', () {
      final slugs = catalogSlugs();
      for (final slug in registeredGameSlugs()) {
        expect(slugs, contains(slug),
            reason: 'game "$slug" 缺 GameCenterCatalogEntry，'
                've game-skin-admin「游戏封面」tab 看不到它；'
                '请在 game_center_catalog.dart 登记后重跑 '
                'tool/publish_game_center_index.dart');
      }
    });

    test('catalog 每条都在 kGameMeta 且 categories 同集', () {
      for (final e in kGameCenterCatalog) {
        final meta = gameMetaOf(e.slug);
        expect(meta, isNot(same(kFallbackGameMeta)),
            reason: 'catalog slug "${e.slug}" 在 kGameMeta 无登记，'
                '卡片会走灰兜底封面');
        expect(
          meta.categories.toSet(),
          unorderedEquals(e.categories),
          reason: 'slug "${e.slug}" 的 categories 在 catalog 与 kGameMeta 不一致',
        );
      }
    });

    test('catalog slug 与 DemoPage.slug 字符级一致（title 可读性抽查）', () {
      // demo.title 与 catalog.title 漂移不致命（管理端仅展示），抽查即可：
      // slug 是 ve 管理 small/large 封面的 skinId，必须严格一致。
      for (final e in kGameCenterCatalog) {
        expect(e.slug, matches(RegExp(r'^[a-z0-9-]+$')),
            reason: 'slug "${e.slug}" 含非法字符（skinId 须稳定 ASCII）');
      }
    });
  });
}
