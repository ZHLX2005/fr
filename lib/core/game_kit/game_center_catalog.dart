// 游戏中心目录 — 唯一事实源（fr → KV → ve 管理端）
//
// 职责：把 fr 当前的游戏中心分类「登记表」发布给 ve 的 game-skin-admin
// 「游戏封面」tab 使用（ve 不再手维护游戏列表，新增/下线游戏只改这里 + 重发 KV）。
//
// 与 fr 其他登记表的关系：
//   · slug      —— 必须与 `DemoPage.slug` 字符级一致（fr://lab/demo/{slug}）
//   · categories —— 必须与 `const_game_center.dart` 的 `GameCategory.*` 常量一致
//                    （本文件刻意不 import Flutter，保持纯 Dart 以便 tool 直接引用）
//   · title / description —— 应与对应 demo 的 `DemoPage.title / description` 保持一致
//
// 发布命令（登录 kvcli 后）：
//   dart run tool/publish_game_center_index.dart
// 发布产物：KV public `game-center_catalog:index`（groupId 190，tag game-center-catalog）
//
// 新增游戏步骤：① demo override `type => DemoType.game`；② 在 [kGameCenterCatalog]
// 登记一条（slug/title/description/mode/categories）；③ 到 const_game_center.dart 的
// [kGameMeta] 补 icon/gradient/pattern；④ 重跑发布命令。
// 防漂移：GameCenterPage.initState 在 debug 模式断言 catalog 与注册表/kGameMeta 一致。

import 'dart:convert';

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

/// 游戏中心目录（发布顺序 = 客户端注册顺序：联机在前，本地在后）。
/// slug 必须与 DemoPage.slug 一致；categories 必须与 GameCategory 常量一致。
const List<GameCenterCatalogEntry> kGameCenterCatalog = [
  // ── 联机（Relay v3 · Lua 状态机）────────────────────────────
  GameCenterCatalogEntry(
    slug: 'surround-game-lua',
    title: '围追堵截（联机）',
    description: 'Quoridor 互联网双人对战 · Lua 服务端权威棋谱',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'gomoku-lua',
    title: '五子棋（联机）',
    description: 'Gomoku 互联网双人对战 · Lua 服务端权威棋谱',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'go-lua',
    title: '围棋（联机）',
    description: 'Go 互联网双人对战 · Lua 服务端权威棋谱',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'team-card-lua',
    title: '团建卡牌（联机）',
    description: '谁是卧底/狼人杀 · Lua 服务端权威 + 三区大厅',
    categories: ['multiplayer', 'party'],
    mode: '联机多人',
  ),
  GameCenterCatalogEntry(
    slug: 'tetris-lua',
    title: '俄罗斯方块（联机）',
    description: 'Tetris 互联网双人对战 · 共享序列 + 实时比拼',
    categories: ['multiplayer', 'arcade'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'coup-lua',
    title: '政变（联机）',
    description: 'Coup 互联网多人对抗 · Lua 服务端权威 + 角色卡 + 质疑/阻断',
    categories: ['multiplayer', 'party'],
    mode: '联机多人',
  ),
  GameCenterCatalogEntry(
    slug: 'reversi-lua',
    title: '黑白翻转棋',
    description: '棋游+联机 · Othello 互联网双人对战 · Lua 服务端权威棋谱',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'chess-online',
    title: '国际象棋（联机）',
    description: 'Chess 互联网双人对战 · v3 Lua 服务端权威',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'jungle-chess-lua',
    title: '斗兽棋（联机）',
    description: '斗兽棋互联网双人对战 · Lua 服务端权威棋谱 · 棋盘对称翻转',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  // ── 本地 ────────────────────────────────────────────────────
  GameCenterCatalogEntry(
    slug: 'surround-game',
    title: '围追堵截',
    description: '本地双人对战',
    categories: ['board'],
    mode: '本地双人',
  ),
  GameCenterCatalogEntry(
    slug: 'jungle-chess',
    title: '斗兽棋',
    description: '本地双人斗兽棋',
    categories: ['board'],
    mode: '本地双人',
  ),
  GameCenterCatalogEntry(
    slug: 'snake',
    title: '贪吃蛇',
    description: '经典贪吃蛇游戏',
    categories: ['arcade'],
    mode: '单人',
  ),
  GameCenterCatalogEntry(
    slug: 'game-2048',
    title: '2048',
    description: '经典数字益智游戏',
    categories: ['puzzle'],
    mode: '单人',
  ),
  GameCenterCatalogEntry(
    slug: 'line',
    title: '线',
    description: '线',
    categories: ['music'],
    mode: '单人',
  ),
];

/// KV value 形状：JSON array，与 `game-center_skin:index`（皮肤索引）同构、可被
/// ve 管理端与未来任何消费方直接 parse。
String gameCenterCatalogJson() =>
    jsonEncode(kGameCenterCatalog.map((e) => e.toJson()).toList());
