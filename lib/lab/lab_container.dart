// IoC 容器 - 控制反转实现
// 用于管理和注册 Demo 页面

import 'package:flutter/material.dart';

/// Demo 页面基类
///
/// slug 设计原则：
/// - slug **必须**纯 ASCII（小写字母/数字/连字符），用于 `fr://lab/demo/{slug}`。
/// - slug 与 title 在子类文件内 **co-located**：新增 demo 时单文件声明，
///   无需跳到 lab_container 维护全局 map。
/// - 为什么必须 ASCII：`Uri.decodeComponent` 对原始中文字符串会抛
///   `Illegal percent encoding`，导致含中文的 fr:// URL 解析崩溃。
///   详见 reffenrece/Flutter-fr路由-注册规范与防腐蚀.md。
abstract class DemoPage {
  /// 人类可读的中文/英文标题（用于 UI 展示）
  String get title;

  /// 简短描述，用于卡片副标题
  String get description;

  /// fr:// 路由 slug，纯 ASCII，每个 demo **必须**显式声明。
  /// 命名约定：小写字母 + 数字 + 连字符。
  ///
  /// 示例：`'clock'`、`'rive-demo'`、`'notion-image-host'`。
  String get slug;

  Widget buildPage(BuildContext context);

  /// 为 true 时，_DemoDetailPage 不显示 AppBar，demo 自行管理全屏布局
  bool get preferFullScreen => false;

  /// Demo 分类；默认 util（通用/工具）。
  /// 游戏类 demo 需 override 为 [DemoType.game] 以接入游戏中心。
  DemoType get type => DemoType.util;

  /// 时间页：true 时在 Focus 主页显示入口，并从 Lab 列表隐藏。
  /// 与 [type] 正交（一个 demo 可同时是 game 或 util，timePage 只决定是否进 Focus）。
  bool get timePage => false;
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

/// 过滤出标记了 [DemoPage.timePage] == true 的条目。供 Focus 主页查
/// `demoRegistry.getAll().filterByTimePage()` 使用 —— 与 gamecenter 的
/// `filterByType(DemoType.game)` 对称。
extension DemoTimePageFilter on Iterable<MapEntry<String, DemoPage>> {
  List<MapEntry<String, DemoPage>> filterByTimePage() =>
      where((e) => e.value.timePage).toList();
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
  /// 传入 [key] 可覆盖（如特殊别名 / 兼容历史 slug）。
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

// 游戏子分类（GameCategory）与每款游戏的展示元数据已迁至
// lib/screens/profile/lab/game_center/const_game_center.dart —
// 分类是游戏中心的 UI 概念，不应污染 demo 容器层。
