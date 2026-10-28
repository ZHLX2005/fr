// 快捷导航目录：系统壳（含 AI 中心）+ 每个 Demo 单元。
//
// Icon 解析优先级（游戏 / lab demo）：
//   1. DemoPage.navIcon（可选 override）
//   2. kGameMeta[slug].icon（游戏）
//   3. 按 DemoType 的默认 Material icon
//
// 系统入口的 icon 在本文件静态登记，与 demo 解耦。

import 'package:flutter/material.dart';

import '../../lab/lab_container.dart';
import '../../screens/containers/ai_container.dart';
import '../../screens/profile/lab/demo_detail_page.dart';
import '../game_center/game_meta.dart';
import '../../screens/containers/game_center_container.dart';
import '../../screens/containers/lab_container.dart';
import '../../screens/containers/profile_container.dart';
import '../../screens/containers/theme_container.dart';
import '../ui/lab/icons/main.dart';
import '../../screens/containers/time_container.dart';
import 'nav_builder_registry.dart';
import 'nav_entry.dart';

export 'nav_entry.dart';

/// 设置入口 id：底栏末槽直连与 ⋯ sheet「设置」按钮共用。
const kSettingsNavId = 'core-settings';

/// Demo 未声明 [DemoPage.navIcon] 时的类型默认图标。
IconData defaultIconForDemoType(DemoType type) => switch (type) {
      DemoType.game => Icons.sports_esports_outlined,
      DemoType.tool => Icons.build_outlined,
      DemoType.util => Icons.widgets_outlined,
    };

/// 解析单个 demo 的导航图标。
IconData resolveDemoNavIcon(DemoPage demo) {
  final override = demo.navIcon;
  if (override != null) return override;
  if (demo.type == DemoType.game) {
    final meta = kGameMeta[demo.slug];
    if (meta != null) return meta.icon;
  }
  return defaultIconForDemoType(demo.type);
}

/// 构建完整可钉选目录（每次读取 registry，保证 bootstrap 后最新）。
List<NavEntry> buildNavCatalog() {
  final entries = <NavEntry>[
    // ── 核心 / 浏览壳 ─────────────────────────────────────────
    NavEntry(
      id: 'core-time',
      title: 'Time',
      icon: Icons.timer_outlined,
      group: NavGroup.core,
      subtitle: '专注',
      builder: (_) => const FocusHomePage(),
    ),
    NavEntry(
      id: kLabNavId,
      title: '实验室',
      icon: Icons.science_outlined,
      group: NavGroup.core,
      subtitle: '工具浏览壳',
      builder: (_) => const LabPage(),
    ),
    NavEntry(
      id: 'core-games',
      title: '游戏中心',
      icon: Icons.sports_esports_rounded,
      group: NavGroup.core,
      subtitle: '封面浏览壳',
      builder: (_) => const GameCenterPage(),
    ),
    NavEntry(
      id: 'core-profile',
      title: '个人',
      icon: Icons.person_outline_rounded,
      group: NavGroup.core,
      subtitle: 'Banner / 彩蛋（可选钉选）',
      builder: (_) => const ProfilePage(),
    ),
    NavEntry(
      id: kSettingsNavId,
      title: '设置',
      icon: Icons.settings_outlined,
      group: NavGroup.core,
      subtitle: '主题与快捷导航',
      // 具体 Page 由 registerNavBuilders() 注册，避免与 settings 循环 import
      builder: (c) => buildRegisteredNavPage('core-settings', c),
    ),
    NavEntry(
      id: 'core-theme',
      title: '主题',
      icon: Icons.palette_outlined,
      group: NavGroup.core,
      subtitle: '外观',
      builder: (_) => const ThemePage(),
    ),

    // AI 中心：整个 AI 板块作为核心组的「一个模块」入口。
    // 子功能（Agent / Format / 小票 / 小助手 / pi）由 HomePage 页内列表承载，
    // 目录不再把子元素拆成独立钉选单元。
    NavEntry(
      id: 'core-ai',
      title: 'AI 中心',
      icon: Icons.assistant,
      group: NavGroup.core,
      subtitle: '助手 / Agent / 小票 / pi',
      builder: (_) => const HomePage(),
    ),
  ];

  // ── 每个 demo = 一个钉选单元 ────────────────────────────────
  // 别名去重：demoRegistry.register(demo, key: alias) 会让同一 demo 实例在
  // getAll() 里出现多次（key 不同、value 同）。此处按**实例**去重，保留注册
  // 时首个 slug —— 与 Lab 列表（lab_page.dart）的去重口径一致。
  // 不去重会出现同一 demo 生成多个**同 id** 的钉选项（设置钉选区/底栏候选
  // 里出现四张一样的 Rive 图标格子）。
  final seenDemos = <DemoPage>{};
  for (final e in demoRegistry.getAll()) {
    final demo = e.value;
    if (!seenDemos.add(demo)) continue;
    // timePage 已并入 Focus，仍可作为独立钉选（需要时可开）
    final group = demo.type == DemoType.game ? NavGroup.game : NavGroup.lab;
    // demo 专属 SVG（Lab 图标集）；未登记的保持 null 走 Material icon
    final kind = labIconForDemoSlug(demo.slug);
    entries.add(
      NavEntry(
        id: demoNavId(demo.slug),
        title: demo.title,
        icon: resolveDemoNavIcon(demo),
        group: group,
        subtitle: demo.description,
        labIconAsset: kind.isFallback ? null : kind.assetBaseName,
        builder: (_) => DemoDetailPage(demo: demo),
      ),
    );
  }

  return entries;
}

final Map<String, NavEntry> _cacheById = {};

/// id → entry；目录随 registry 变化时调用 [invalidateNavCatalogCache]。
NavEntry? navEntryById(String id) {
  if (_cacheById.isEmpty) {
    for (final e in buildNavCatalog()) {
      _cacheById[e.id] = e;
    }
  }
  return _cacheById[id];
}

void invalidateNavCatalogCache() => _cacheById.clear();

List<NavEntry> navEntriesInGroup(NavGroup group) =>
    buildNavCatalog().where((e) => e.group == group).toList();
