// IoC 容器 - 控制反转实现
// 用于管理和注册 Demo 页面

import 'package:flutter/material.dart';

/// demo title → URL slug 映射表。
///
/// slug 必须是纯 ASCII（小写字母/数字/连字符），用于 `fr://lab/demo/{slug}`。
/// 集中维护，避免改 37 个 demo 类。新增 demo 时在此加一行。
///
/// 为什么需要 slug：`Uri.decodeComponent` 对原始中文字符串会抛
/// `Illegal percent encoding`，导致含中文的 fr:// URL 解析崩溃。
/// 用 ASCII slug 彻底规避。详见 reffenrece/Flutter-fr路由-注册规范与防腐蚀.md。
const Map<String, String> kDemoSlugs = {
  '时钟': 'clock',
  '日历待办': 'calendar',
  '悬浮截屏': 'overlay',
  'Notion 图床': 'notion-image-host',
  'Crash日志': 'crash-log',
  '网络': 'network',
  'LocalNet': 'localnet',
  'GitHub': 'github',
  '自由画布': 'free-canvas',
  '线': 'line',
  '斗兽棋': 'jungle-chess',
  '图库管理': 'gallery',
  '撞色色卡': 'color-palette',
  'Demo 实验室': 'demo-lab',
  '2048': 'game-2048',
  'Double Time': 'double-time',
  '网格视图': 'grid-dashboard',
  '身体记录': 'body-map',
  '底部导航条': 'bottom-bar',
  'Rive 摆钟': 'rive-pendulum',
  '组数追踪': 'set-tracker',
  '存储分析': 'storage-analyze',
  'Rive 数据绑定': 'rive-data-bind',
  '贪吃蛇': 'snake',
  '单词拖拽': 'word-drag',
  '围追堵截': 'surround-game',
  '堆叠色卡': 'stack-card',
  '黑白翻转棋': 'reversi',
  '音量衰减': 'volume-decay',
  '传感器': 'sensor',
  'Web Bookmarks': 'web-bookmark',
  '二维码': 'qr',
  'Schema链接': 'schema',
  '手电筒': 'torch',
  'API 测试': 'api-test',
  '调色板': 'pigment-palette',
  '块编辑器': 'block-editor',
  'Novel Reader': 'novel-reader',
  '反应力测试': 'reaction-test',
};

/// Demo 页面基类
abstract class DemoPage {
  String get title;
  String get description;
  Widget buildPage(BuildContext context);

  /// 为 true 时，_DemoDetailPage 不显示 AppBar，demo 自行管理全屏布局
  bool get preferFullScreen => false;

  /// Demo 分类；默认 util（通用/工具）。
  /// 游戏类 demo 需 override 为 [DemoType.game] 以接入游戏中心。
  DemoType get type => DemoType.util;

  /// URL slug（ASCII，用于 `fr://lab/demo/{slug}`）。
  /// 默认从 [kDemoSlugs] 查 title；未命中返回 title（向后兼容，
  /// 但中文 title 的 demo 应在 kDemoSlugs 注册英文 slug）。
  String get slug => kDemoSlugs[title] ?? title;
}

/// Demo 分类 - 用于按类型过滤（如游戏中心）
enum DemoType { util, tool, game }

extension DemoTypeFilter on Iterable<MapEntry<String, DemoPage>> {
  /// 按 demo.type 过滤注册表条目。
  ///
  /// 使用示例：
  /// ```dart
  /// final games = demoRegistry.getAll().filterByType(DemoType.game);
  /// ```
  List<MapEntry<String, DemoPage>> filterByType(DemoType t) =>
      where((e) => e.value.type == t).toList();
}

/// Demo 注册表
///
/// 双索引：slug 主索引（URL 路由查），title 副索引（autoLink / 兼容查询）。
/// [getAll] 返回 slug 作 key 的 entries（URL 生成用 slug）。
class DemoRegistry {
  static final DemoRegistry _instance = DemoRegistry._internal();
  factory DemoRegistry() => _instance;
  DemoRegistry._internal();

  final Map<String, DemoPage> _bySlug = {};
  final Map<String, DemoPage> _byTitle = {};

  /// 注册 demo。
  ///
  /// [key] 不传则用 [DemoPage.slug]（ASCII，推荐）。
  /// 传入 [key] 可覆盖（如特殊别名）。
  void register(DemoPage demo, {String? key}) {
    final slug = key ?? demo.slug;
    _bySlug[slug] = demo;
    _byTitle[demo.title] = demo;
  }

  /// 全部 demo，key 是 slug（用于生成 fr://lab/demo/{slug}）。
  List<MapEntry<String, DemoPage>> getAll() {
    return _bySlug.entries.toList();
  }

  /// 按 slug 或 title 查（兼容老调用方）。
  ///
  /// 优先查 slug；miss 再查 title（向后兼容中文 key 调用）。
  DemoPage? get(String key) => _bySlug[key] ?? _byTitle[key];

  /// 仅按 slug 查。
  DemoPage? getBySlug(String slug) => _bySlug[slug];

  /// 仅按 title 查（autoLink 用：文本里匹配中文 title → 找 demo → 取 slug）。
  DemoPage? getByTitle(String title) => _byTitle[title];

  int get count => _bySlug.length;
}


/// 全局 Demo 注册表 - 在 main.dart 初始化时注册
final demoRegistry = DemoRegistry();

/// 路由名称常量
class LabRoutes {
  static const String lab = '/lab';
  static const String demo = '/lab/demo';
}

/// 游戏子分类常量 — 仅作为字符串 key 供 GameCenterPage 分桶。
///
/// 不在 DemoPage 上加新字段：分类是 UI 概念，归类由 GameCenterPage._categoryOf
/// 用 is-类型判断完成。这样 5 个 game demo 文件保持零侵入。
class GameCategory {
  GameCategory._();

  /// 占位"全部" tab — 不参与 demo 归类，仅作为 TabBar 第一个标签。
  static const String all = 'all';

  /// 街机（如：贪吃蛇）
  static const String arcade = 'arcade';

  /// 联机（如：围追堵截）
  static const String multiplayer = 'multiplayer';

  /// 棋游（如：黑白翻转棋）
  static const String board = 'board';

  /// 益智（如：2048）
  static const String puzzle = 'puzzle';

  /// 音游（如：线）
  static const String music = 'music';

  /// 收藏（按 LabCardProvider.isFavorite 过滤全集）
  static const String favorites = 'favorites';
}
