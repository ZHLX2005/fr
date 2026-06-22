/// IoC 容器 - 控制反转实现
/// 用于管理和注册 Demo 页面

import 'package:flutter/material.dart';

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
class DemoRegistry {
  static final DemoRegistry _instance = DemoRegistry._internal();
  factory DemoRegistry() => _instance;
  DemoRegistry._internal();

  final Map<String, DemoPage> _demos = {};

  void register(DemoPage demo, {String? key}) {
    final demoKey = key ?? demo.title;
    _demos[demoKey] = demo;
  }

  List<MapEntry<String, DemoPage>> getAll() {
    return _demos.entries.toList();
  }

  DemoPage? get(String key) => _demos[key];

  int get count => _demos.length;
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
