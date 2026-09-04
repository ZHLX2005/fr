// lib/core/game_kit/skin/game_skin_spec.dart
//
// 通用皮肤规约（GameSkinSpec）—— 泛化 chess 已有管线的"命名派生"层。
//
// 命名约定（见 plan/game-kit-unification.md §Naming Convention）：
//   gameId 塌缩为单个字符串，其余全部派生：
//   - KV key:            <game>_skin:index     e.g. chess_skin:index / gomoku_skin:index
//   - KV tag:            <game>-skin           e.g. chess-skin / gomoku-skin
//   - file key 前缀:      <game>/<skinId>/...   e.g. gomoku/1/black
//   - 本地缓存目录:       <game>_skins          e.g. chess_skins / gomoku_skins
//   - SharedPreferences:  <game>_skin_id        e.g. chess_skin_id / gomoku_skin_id
//   - groupId:           190（全游戏共享）
//
// 本文件是 Track A 产物的占位实现：若 Track A 已创建更完整的版本，本文件
// 会被其覆盖（幂等）。Track D 仅需 gomoku 条目的最小可用版本来跑通 e2e。

/// 单个游戏的皮肤规约（纯数据，const）。
class GameSkinSpec {
  /// 游戏唯一 id（与 GameLobbySpec.gameId / GameDefinition.slug 一致）。
  final String gameId;

  /// 展示名（调试 / 管理后台用）。
  final String displayName;

  /// 该游戏需要的资源 key 集合（pieces + 可选 board）。
  ///
  /// chess: 12 keys (wK...bp)；gomoku: 3 keys (black/white/board)。
  final Set<String> assetKeys;

  /// KV 索引 key（派生：`<game>_skin:index`）。
  String get kvIndexKey => '${gameId}_skin:index';

  /// KV tag（派生：`<game>-skin`）。
  String get kvTag => '$gameId-skin';

  /// 本地缓存根目录名（派生：`<game>_skins`）。
  String get cacheDirName => '${gameId}_skins';

  /// SharedPreferences key（派生：`<game>_skin_id`）。
  String get prefsKey => '${gameId}_skin_id';

  /// KV public groupId（全游戏共享，见 chess PublicKvReader.kChessSkinPublicGroupId）。
  static const int kGroupId = 190;

  /// groupId（实例访问器，等价 [kGroupId]）。
  int get groupId => kGroupId;

  const GameSkinSpec({
    required this.gameId,
    required this.displayName,
    required this.assetKeys,
  });
}

/// chess 已有 12-key 集合（与 chess_skin_meta.kChessSkin12PieceKeys 对齐，
///
/// 这里重复声明以避免 game_kit 依赖 chess；chess 侧仍以自身常量为准）。
const Set<String> kChessSkinAssetKeys = {
  'wK', 'wQ', 'wR', 'wB', 'wN', 'wp',
  'bK', 'bQ', 'bR', 'bB', 'bN', 'bp',
};

/// gomoku 皮肤所需资源（黑子 / 白子 / 棋盘底图）
///
/// - `black` / `white`：交点落子贴图（圆形石头，建议 webp 正方形）
/// - `board`：棋盘底图（可选，null 时走 BoardColorStrategy.background）
/// 与指令 assetKeys=[black, white, board] 一致。
const Set<String> kGomokuSkinAssetKeys = {
  'black',
  'white',
  'board',
};

/// 已注册的游戏皮肤规约（const）。
const GameSkinSpec kChessSkinSpec = GameSkinSpec(
  gameId: 'chess',
  displayName: '国际象棋',
  assetKeys: kChessSkinAssetKeys,
);

const GameSkinSpec kGomokuSkinSpec = GameSkinSpec(
  gameId: 'gomoku',
  displayName: '五子棋',
  assetKeys: kGomokuSkinAssetKeys,
);

/// 按 gameId 解析规约（未注册的 gameId 返回 null，调用方回退默认行为）。
GameSkinSpec? gameSkinSpecFor(String gameId) {
  switch (gameId) {
    case 'chess':
      return kChessSkinSpec;
    case 'gomoku':
      return kGomokuSkinSpec;
    default:
      return null;
  }
}
