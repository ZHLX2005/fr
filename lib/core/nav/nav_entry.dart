import 'package:flutter/material.dart';

/// 快捷导航分组（设置 Tab / 搜索过滤用）。
enum NavGroup {
  core,
  lab,
  game,
}

/// 核心入口 id：实验室浏览壳（底栏隐匿请求按 id 记名用，见
/// bottomBarVisibilityProvider）。
const kLabNavId = 'core-lab';

/// demo 的钉选 nav id。目录注册与页面内引用（如底栏隐匿请求）共用这份推导，
/// 两处各写字面量会出现「请求挂在 id A、目录注册 id B」的静默失联。
String demoNavId(String slug) => 'demo:$slug';

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
    this.labIconAsset,
  });

  final String id;
  final String title;
  final IconData icon;
  final NavGroup group;

  /// 打开该单元时的页面。
  final WidgetBuilder builder;

  final String? subtitle;

  /// demo 专属 SVG 图标（Lab 图标集 basename，不含 .svg）。
  /// 非 null 时渲染处（底栏 / 设置钉选 / ⋯ 面板）优先用它替代 [icon]；
  /// null（核心入口 / 未登记 demo）走 [icon]。
  final String? labIconAsset;

  String get groupLabel => switch (group) {
        NavGroup.core => '核心',
        NavGroup.lab => '实验室',
        NavGroup.game => '游戏',
      };
}
