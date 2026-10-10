import 'package:flutter/material.dart';

/// 快捷导航分组（设置 Tab / 搜索过滤用）。
enum NavGroup {
  core,
  ai,
  lab,
  game,
}

/// 可钉选单元：1 demo / 1 模块 = 1 [NavEntry]。
///
/// [id] 稳定键（持久化用），禁止用展示文案。
class NavEntry {
  const NavEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.group,
    required this.builder,
    this.subtitle,
  });

  final String id;
  final String title;
  final IconData icon;
  final NavGroup group;

  /// 打开该单元时的页面。
  final WidgetBuilder builder;

  final String? subtitle;

  String get groupLabel => switch (group) {
        NavGroup.core => '核心',
        NavGroup.ai => 'AI',
        NavGroup.lab => '实验室',
        NavGroup.game => '游戏',
      };
}
