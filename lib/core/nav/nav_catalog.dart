// 快捷导航目录：系统壳 + AI 拆分 + 每个 Demo 单元。
//
// Icon 解析优先级（游戏 / lab demo）：
//   1. DemoPage.navIcon（可选 override）
//   2. kGameMeta[slug].icon（游戏）
//   3. 按 DemoType 的默认 Material icon
//
// 系统 / AI 入口的 icon 在本文件静态登记，与 demo 解耦。

import 'package:flutter/material.dart';

import '../../lab/lab_container.dart';
import '../../screens/chat/home_page.dart' show kAssistantEntries;
import '../../screens/profile/lab/demo_detail_page.dart';
import '../../screens/profile/lab/game_center/const_game_center.dart';
import '../../screens/profile/lab/game_center_page.dart';
import '../../screens/profile/lab/lab_page.dart';
import '../../screens/profile/profile_page.dart';
import '../../screens/profile/theme/theme_page.dart';
import '../ai_chat/ai_chat_settings_page.dart';
import '../focus/focus_home_page.dart';
import 'nav_builder_registry.dart';
import 'nav_entry.dart';

export 'nav_entry.dart';

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
      id: 'core-lab',
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
      id: 'core-settings',
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
    NavEntry(
      id: 'ai-settings',
      title: 'AI 设置',
      icon: Icons.tune_outlined,
      group: NavGroup.ai,
      subtitle: '模型与密钥',
      builder: (_) => const AIChatSettingsPage(),
    ),
  ];

  // ── AI 拆分：复用 AssistantEntry 列表 ───────────────────────
  for (final a in kAssistantEntries) {
    entries.add(
      NavEntry(
        id: 'ai-${_slugify(a.title)}',
        title: a.title,
        icon: a.icon,
        group: NavGroup.ai,
        subtitle: a.subtitle,
        builder: a.builder,
      ),
    );
  }

  // ── 每个 demo = 一个钉选单元 ────────────────────────────────
  for (final e in demoRegistry.getAll()) {
    final demo = e.value;
    // timePage 已并入 Focus，仍可作为独立钉选（需要时可开）
    final group = demo.type == DemoType.game ? NavGroup.game : NavGroup.lab;
    entries.add(
      NavEntry(
        id: 'demo:${demo.slug}',
        title: demo.title,
        icon: resolveDemoNavIcon(demo),
        group: group,
        subtitle: demo.description,
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

String _slugify(String title) {
  // 已知中文/展示名 → 稳定 ASCII id
  const map = {
    'Agent': 'agent',
    'Format': 'format',
    '小票': 'receipt',
    '小助手': 'sys-msg',
    'pi': 'pi',
  };
  return map[title] ??
      title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
}
