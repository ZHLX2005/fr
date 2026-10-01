// 游戏中心 — 模块常量集中管理
//
// 这里是游戏中心唯一的「登记处」：分类、每款游戏的分类归属 / 图标 / 配色 /
// 封面图案 / 玩法标签、以及页面布局尺寸。UI 文件只读这里，不再散落魔法值。
//
// 添加新游戏三步：
//   ① 让 demo `override DemoType get type => DemoType.game`
//   ② 在 [kGameMeta] 里按 **slug** 加一条（slug 是 DemoPage.slug，纯 ASCII 稳定键）
//   ③ 若引入新分类，往 [GameCategory] + [kGameCategoryTabs] + [kGameCategoryIcons] 各加一行
//
// 为什么按 slug 而不是 `is DemoClass` 判类型：常量层不依赖任何 demo 实现文件，
// 新增/删除游戏不会牵动 import 图，也避免游戏中心反向耦合 lab/demos。
//
// 主题豁免：[kGameMeta] 内各 `gradient: [Color(0xFF...), Color(0xFF...)]` 是各游戏的
// 封面艺术设计身份（非 UI 通用色），跟随游戏识别保留硬编码。

import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════
// 分类
// ══════════════════════════════════════════════════════════════

/// 游戏子分类 key。仅供游戏中心分桶使用，不写进 DemoPage 字段。
class GameCategory {
  GameCategory._();

  /// 收藏（按 LabCardProvider.isFavorite 过滤全集），不参与 [kGameMeta] 归类
  static const String favorites = 'favorites';

  /// 全部，不参与 [kGameMeta] 归类
  static const String all = 'all';

  /// 联机（走 Relay/Lua 服务端的互联网对战）
  static const String multiplayer = 'multiplayer';

  /// 棋游
  static const String board = 'board';

  /// 街机
  static const String arcade = 'arcade';

  /// 益智
  static const String puzzle = 'puzzle';

  /// 派对（团建 / 多人围坐）
  static const String party = 'party';

  /// 音游
  static const String music = 'music';
}

/// Tab / 过滤 chip 的显示顺序与文案。改顺序 = 改这个列表。
const List<({String category, String label})> kGameCategoryTabs = [
  (category: GameCategory.all, label: '全部'),
  (category: GameCategory.favorites, label: '收藏'),
  (category: GameCategory.multiplayer, label: '联机'),
  (category: GameCategory.board, label: '棋游'),
  (category: GameCategory.arcade, label: '街机'),
  (category: GameCategory.puzzle, label: '益智'),
  (category: GameCategory.party, label: '派对'),
  (category: GameCategory.music, label: '音游'),
];

/// 分类 → 图标（过滤 chip 与卡片标签共用）
const Map<String, IconData> kGameCategoryIcons = {
  GameCategory.all: Icons.apps_rounded,
  GameCategory.favorites: Icons.star_rounded,
  GameCategory.multiplayer: Icons.wifi_tethering_rounded,
  GameCategory.board: Icons.grid_4x4_rounded,
  GameCategory.arcade: Icons.sports_esports_rounded,
  GameCategory.puzzle: Icons.extension_rounded,
  GameCategory.party: Icons.celebration_rounded,
  GameCategory.music: Icons.graphic_eq_rounded,
};

/// 分类 → 中文短标签（卡片上的角标文案）
const Map<String, String> kGameCategoryLabels = {
  GameCategory.multiplayer: '联机',
  GameCategory.board: '棋游',
  GameCategory.arcade: '街机',
  GameCategory.puzzle: '益智',
  GameCategory.party: '派对',
  GameCategory.music: '音游',
};

// ══════════════════════════════════════════════════════════════
// 封面
// ══════════════════════════════════════════════════════════════

/// 程序化封面的装饰图案。没有美术资源时，用图案 + 配色让每款游戏彼此可辨。
enum GameArtPattern {
  /// 柔和光斑（默认）
  blob,

  /// 斜条纹
  stripes,

  /// 网格线（棋盘感）
  grid,

  /// 圆点阵
  dots,

  /// 波形（音游）
  wave,
}

/// 单款游戏的展示元数据。
class GameMeta {
  const GameMeta({
    required this.categories,
    required this.icon,
    required this.gradient,
    required this.mode,
    this.pattern = GameArtPattern.blob,
  });

  /// 所属分类（可多归属：联机五子棋同时进「联机」与「棋游」）
  final Set<String> categories;

  /// 封面主图标
  final IconData icon;

  /// 封面渐变（起止两色，左上 → 右下）
  final List<Color> gradient;

  /// 玩法标签，如「本地双人」「联机双人」
  final String mode;

  /// 封面装饰图案
  final GameArtPattern pattern;

  bool get isOnline => categories.contains(GameCategory.multiplayer);
}

/// slug → 展示元数据。key 必须与 `DemoPage.slug` 完全一致。
const Map<String, GameMeta> kGameMeta = {
  // ── 联机（Relay v3 · Lua 状态机）────────────────────────────
  'surround-game-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.hub_rounded,
    gradient: [Color(0xFF4C3BCF), Color(0xFF6C5CE7)],
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  'gomoku-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.grid_4x4_rounded,
    gradient: [Color(0xFF0F766E), Color(0xFF14B8A6)],
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  'go-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.circle_outlined,
    gradient: [Color(0xFF1E293B), Color(0xFF475569)],  // 黑白灰
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  'team-card-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.party},
    icon: Icons.style_rounded,
    gradient: [Color(0xFFC2185B), Color(0xFFF06292)],
    mode: '联机多人',
    pattern: GameArtPattern.dots,
  ),
  'tetris-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.arcade},
    icon: Icons.grid_view_rounded,
    gradient: [Color(0xFF3A414C), Color(0xFF2AD4E0)], // 主题豁免：tetris Ash
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  'coup-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.party},
    icon: Icons.crisis_alert_rounded,
    gradient: [Color(0xFF7C2D12), Color(0xFFEA580C)],
    mode: '联机多人',
    pattern: GameArtPattern.dots,
  ),
  'reversi-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.cached_rounded,
    gradient: [Color(0xFF1F2937), Color(0xFF4B5563)],
    mode: '联机双人',
    pattern: GameArtPattern.dots,
  ),
  'chess-online': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.sports_esports_rounded,
    gradient: [Color(0xFF78350F), Color(0xFFD97706)],
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  'jungle-chess-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.pets_rounded,
    gradient: [Color(0xFF7C2D12), Color(0xFFB45309)],
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  'sudoku-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.puzzle},
    icon: Icons.grid_on_rounded,
    gradient: [Color(0xFF3D3127), Color(0xFFA07E5A)], // 主题豁免：数独纸墨（sudoku_colors.dart）
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),

  // ── 本地 ────────────────────────────────────────────────────
  // 围追堵截本地版：本地双人对战，归「棋游」，不进「联机」。
  'surround-game': GameMeta(
    categories: {GameCategory.board},
    icon: Icons.route_rounded,
    gradient: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
    mode: '本地双人',
    pattern: GameArtPattern.grid,
  ),
  'reversi': GameMeta(
    categories: {GameCategory.board},
    icon: Icons.album_rounded,
    gradient: [Color(0xFF334155), Color(0xFF64748B)],
    mode: '本地双人',
    pattern: GameArtPattern.dots,
  ),
  'jungle-chess': GameMeta(
    categories: {GameCategory.board},
    icon: Icons.pets_rounded,
    gradient: [Color(0xFF92400E), Color(0xFFD97706)],
    mode: '本地双人',
    pattern: GameArtPattern.grid,
  ),
  'snake': GameMeta(
    categories: {GameCategory.arcade},
    icon: Icons.videogame_asset_rounded,
    gradient: [Color(0xFF15803D), Color(0xFF4ADE80)],
    mode: '单人',
    pattern: GameArtPattern.stripes,
  ),
  'game-2048': GameMeta(
    categories: {GameCategory.puzzle},
    icon: Icons.grid_view_rounded,
    gradient: [Color(0xFFB45309), Color(0xFFF59E0B)],
    mode: '单人',
    pattern: GameArtPattern.blob,
  ),
  'line': GameMeta(
    categories: {GameCategory.music},
    icon: Icons.graphic_eq_rounded,
    gradient: [Color(0xFF6D28D9), Color(0xFFEC4899)],
    mode: '单人',
    pattern: GameArtPattern.wave,
  ),
};

/// 未登记 slug 的兜底元数据（新 game demo 忘了登记也不会崩、不会白板）。
const GameMeta kFallbackGameMeta = GameMeta(
  categories: {GameCategory.arcade},
  icon: Icons.sports_esports_rounded,
  gradient: [Color(0xFF475569), Color(0xFF94A3B8)],
  mode: '单人',
);

/// 取某个 slug 的元数据，miss 时兜底。
GameMeta gameMetaOf(String slug) => kGameMeta[slug] ?? kFallbackGameMeta;

// ══════════════════════════════════════════════════════════════
// 布局尺寸
// ══════════════════════════════════════════════════════════════

/// 页面横向留白
const double kGcPagePadding = 16.0;

/// 卡片圆角
const double kGcCardRadius = 18.0;

// 顶部功能行（返回热区 + 搜索框合体胶囊）—— H3R2-V3「合体胶囊」方案：
// 整行只剩一根描边胶囊，返回键内嵌在胶囊左端（细分隔线隔开），
// 「返回键与搜索框的占比」从结构上不存在。视觉规格源自
// temp/game-center-header-ui/h3r2-proportion/v3-merged-capsule.html 定稿。

/// 胶囊高度（= 功能行高）
const double kGcTopRowHeight = 44.0;

/// 状态栏 → 功能行的间距（有刘海/状态栏 inset 的机型用 inset + 此值）
const double kGcTopRowGapTop = 12.0;

/// 无状态栏 inset（桌面 web / 横屏）时的默认顶部间距，避免功能行贴顶
const double kGcTopRowGapTopFallback = 16.0;

/// 功能行 → 内容区（分节标题）的间距
const double kGcTopRowGapBottom = 12.0;

/// 搜索框描边宽度（border-emphasis：透明底，靠主题色描边定义形状）
const double kGcSearchBorderWidth = 2.0;

/// 搜索框圆角（胶囊整体）
const double kGcSearchRadius = 13.0;

/// 胶囊左端返回热区宽度
const double kGcBackZoneWidth = 44.0;

/// 胶囊内返回热区与搜索区之间的分隔线宽度
const double kGcBackZoneDividerWidth = 1.0;

/// 搜索区左内边距（返回热区分隔线 → 搜索图标）
const double kGcSearchZonePadLeft = 13.0;

/// 搜索区右内边距（「搜索」提交钮 → 胶囊描边）
const double kGcSearchZonePadRight = 6.0;

/// 搜索框内嵌「搜索」提交钮高度
const double kGcSearchButtonHeight = 32.0;

/// 精选横滑卡高度
const double kGcFeaturedHeight = 196.0;

/// 网格单元最大宽度 —— 用 MaxCrossAxisExtent 让列数随屏宽自适应，
/// 避免写死 crossAxisCount 在平板/折叠屏上过疏。
const double kGcGridMaxExtent = 210.0;

/// 网格单元宽高比
const double kGcGridAspectRatio = 0.80;

/// 入场动画节奏（喂给共享 RevealItem；比 Lab 网格稍快、位移稍小）
const double kGcRevealDelayStep = 0.05;
const double kGcRevealMaxDelay = 0.6;
const double kGcRevealItemDuration = 0.3;
const double kGcRevealTranslateY = 20.0;

/// 滚动到该偏移时，毛玻璃标题条完全淡入。
/// 头部区总高 = topGap + 胶囊 44 + bottomGap（约 68px），
/// 再加一档余量：头部刚滑出视野就开始出现，滑过半屏细条已完全实。
const double kGcGlassBarThreshold = 68.0;

// ══════════════════════════════════════════════════════════════
// 搜索
// ══════════════════════════════════════════════════════════════

/// 搜索历史在 SharedPreferences 的存储键（字符串列表，最新在前，封顶去重）
const String kGcSearchHistoryKey = 'game_center_search_history';

/// 搜索历史最多保留条数
const int kGcSearchHistoryMax = 8;
