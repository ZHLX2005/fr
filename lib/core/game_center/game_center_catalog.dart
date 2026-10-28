// 游戏中心目录 — 运行时派生（fr 注册表 → KV → ve 管理端）
//
// 目录不再手工登记：[buildGameCenterCatalog] 每次从 demoRegistry
//（DemoType.game）与 `const_game_center.dart` 的 kGameMeta 现算——
// 游戏增删只改 demo / kGameMeta 本身，目录随之而变，不存在第二份副本。
//
// 同步机制（见 game_center_catalog_sync.dart）：
//   GameCenterPage 打开时把派生结果与 KV 当前值比对，有差异且已登录
//  （owner/admin）才写回 —— 打开一次游戏中心即完成同步，ve game-skin-admin
//   「游戏封面」tab 刷新可见，无需任何手动发布。
//
// KV 产物：public `game-center_catalog:index`（groupId 190，
// tag game-center-catalog），ve 端匿名读，与 `game-center_skin:index`
//（封面索引）同构、可被任何消费方直接 parse。
//
// 字段来源（派生规则）：
//   slug        —— DemoPage.slug（= ve 侧 skinId，字符级稳定键）
//   title       —— DemoPage.title
//   description —— DemoPage.description
//   categories  —— kGameMeta[slug].categories（GameCategory 常量）
//   mode        —— kGameMeta[slug].mode
//   isOnline    —— categories 含 multiplayer
//
// 历史：本文件曾有 17 条手工 kGameCenterCatalog 常量表 +
// tool/publish_game_center_index.dart 手动发布；「登记」与「发布」两步都会
// 被忘（2026-10-25 国际跳棋/中国象棋因此缺席 ve 端），已一并删除。

import 'dart:convert';

import '../../lab/lab_container.dart';
import 'game_meta.dart';

/// 单款游戏的目录条目（JSON 序列化的形状就是 KV value 的元素）。
class GameCenterCatalogEntry {
  const GameCenterCatalogEntry({
    required this.slug,
    required this.title,
    required this.description,
    required this.categories,
    required this.mode,
  });

  /// fr demo slug（= skinId，ve 用它管理 small/large 封面）
  final String slug;

  /// 游戏显示名（= demo.title）
  final String title;

  /// 一句话描述（= demo.description）
  final String description;

  /// 分类 key 列表（GameCategory 常量：multiplayer/board/arcade/puzzle/party/music）
  final List<String> categories;

  /// 玩法标签，如「联机双人」「本地双人」「单人」
  final String mode;

  bool get isOnline => categories.contains('multiplayer');

  Map<String, Object> toJson() => {
        'slug': slug,
        'title': title,
        'description': description,
        'mode': mode,
        'categories': categories,
        'isOnline': isOnline,
      };
}

/// 从注册好的 game demo 列表派生目录（顺序 = 传入顺序 = 客户端注册顺序）。
///
/// [games] 通常传 GameCenterPage 已经算好的 `_games`
///（demoRegistry.getAll().filterByType(DemoType.game) 去重后的列表）。
/// categories/mode 取 kGameMeta；未登记 slug 走 kFallbackGameMeta 兜底
///（debug 断言与 flutter test 会拦，见 game_center_catalog_test）。
List<GameCenterCatalogEntry> buildGameCenterCatalog(List<DemoPage> games) =>
    [for (final d in games) _entryOf(d)];

GameCenterCatalogEntry _entryOf(DemoPage d) {
  final meta = gameMetaOf(d.slug);
  return GameCenterCatalogEntry(
    slug: d.slug,
    title: d.title,
    description: d.description,
    categories: meta.categories.toList(),
    mode: meta.mode,
  );
}

/// KV value 形状：JSON array，与 `game-center_skin:index`（皮肤索引）同构。
/// 输入相同则输出逐字节相同 —— 这是 compare-then-write 幂等的前提
///（测试 game_center_catalog_test 有确定性断言把关）。
String gameCenterCatalogJson(List<GameCenterCatalogEntry> entries) =>
    jsonEncode(entries.map((e) => e.toJson()).toList());
