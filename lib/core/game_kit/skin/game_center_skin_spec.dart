// lib/core/game_kit/skin/game_center_skin_spec.dart
//
// 游戏中心封面皮肤规约 —— 封面管线接入（ve game-skin-admin → KV public → 客户端）。
//
// 设计：游戏中心不是一款游戏，而是各游戏封面的合集：
//   - skinId = demo.slug（与 kGameMeta / GameDefinition.slug 字符级一致）
//   - 每个 skin 两个资产：
//       small：网格卡封面（建议 1.2:1，如 512×432）
//       large：轮播大卡封面（建议 16:9，如 960×540）
//   - 派生（GameSkinSpec）：KV key = game-center_skin:index，tag = game-center-skin，
//     缓存目录 = game-center_skins，groupId = 190
//
// 客户端接入点：
//   GameCenterPage.initState → fetchAndMergeGameCenterSkins()（best-effort）
//   卡片渲染 → gameCenterCoverOf(slug, 'small' | 'large')
//   未上传/未命中 → 返回 null，GameArtwork 回退程序化封面。

import 'package:flutter/widgets.dart' show ImageProvider;

import 'file_resolver.dart';
import 'game_skin_bundle.dart';
import 'game_skin_meta_sync.dart';
import 'game_skin_spec.dart';
import 'public_kv_reader.dart';

/// 游戏中心封面资产 key：卡片小图 / 轮播大图
const Set<String> kGameCenterSkinAssetKeys = {'small', 'large'};

/// 卡片小图资产 key（网格卡封面）
const String kGameCenterSkinSmall = 'small';

/// 轮播大图资产 key（精选/收藏轮播卡封面）
const String kGameCenterSkinLarge = 'large';

/// 游戏中心封面规约。
const GameSkinSpec kGameCenterSkinSpec = GameSkinSpec(
  gameId: 'game-center',
  displayName: '游戏中心',
  assetKeys: kGameCenterSkinAssetKeys,
);

/// 默认后端 base URL（与 chess/gomoku 皮肤管线同一 host）
const String kDefaultGameCenterSkinBaseUrl = 'http://47.110.80.47:8988';

/// 游戏中心封面注册表单例（KV 拉取后按 slug 合入；未拉取时为空，渲染回退程序化）。
final GameSkinBundle gameCenterSkinBundle = GameSkinBundle(kGameCenterSkinSpec);

/// 拉取 `game-center_skin:index` 并合入 [gameCenterSkinBundle]。
///
/// best-effort：网络失败 / KV 缺失 / 解析失败一律静默返回 false，封面回退程序化。
Future<bool> fetchAndMergeGameCenterSkins({
  PublicKvReader? reader,
  FileResolver? resolver,
  String defaultBaseUrl = kDefaultGameCenterSkinBaseUrl,
}) {
  return fetchAndMergeSkinsFor(
    gameCenterSkinBundle,
    reader: reader,
    resolver: resolver,
    defaultBaseUrl: defaultBaseUrl,
  );
}

/// 取某款游戏（[slug]）指定资产（[assetKey]，small/large）的封面 [ImageProvider]。
///
/// 未上传 / 未命中 / 拉取失败时返回 null，调用方回退程序化封面，绝不抛。
ImageProvider? gameCenterCoverOf(String slug, String assetKey) {
  return gameCenterSkinBundle.byId(slug).pieces[assetKey];
}
