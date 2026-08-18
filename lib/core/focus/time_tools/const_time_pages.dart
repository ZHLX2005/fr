// 时间页（timePage）展示元数据 —— 对应 game_center 的 kGameMeta。
//
// 同样的取舍：常量层不 import 任何 demo 实现文件，按 demo.slug 查。
// 添加新时间页三步：
//   ① 让 demo `override bool get timePage => true;`
//   ② 在 [kTimePageMeta] 里按 slug 加一条
//   ③ 若引入新排序规则，更新 [FocusHomePage] 的 featured 选择
//
// icon 跟随现有 focus 莫兰迪卡（sage 主基调），强调色由 [colorFor] 按 slug 从
// ColorScheme 派生（sage 家族豁免，calendar/节拍器走 scheme 派生）。
import 'package:flutter/material.dart';

/// 单个 timePage demo 的展示元数据。
class TimePageMeta {
  const TimePageMeta({
    required this.label,
    required this.icon,
    this.featured = false,
  });

  /// 覆盖 [DemoPage.title]（如 'Clock' → '时钟'），统一中文。
  final String label;

  /// 卡片主图标。
  final IconData icon;

  /// true → 占 Focus 主页的精选大卡（一张）。目前只有 clock。
  final bool featured;
}

/// slug → 展示元数据。key 必须与 [DemoPage.slug] 完全一致。
///
/// 主题豁免：sage 家族色 (B5C9A3) —— 与"今日专注卡"同色系，zen 风格识别，
/// 不跟随主题切换。
const Map<String, TimePageMeta> kTimePageMeta = {
  'clock': TimePageMeta(
    label: '时钟',
    icon: Icons.access_time_rounded,
    featured: true,
  ),
  'calendar': TimePageMeta(
    label: '日历',
    icon: Icons.calendar_month_outlined,
  ),
  'metronome': TimePageMeta(
    label: '节拍器',
    icon: Icons.music_note_outlined,
  ),
};

/// 未登记 slug 的兜底元数据（防御性：避免 UI 上 null 字段）。
const TimePageMeta kFallbackTimePageMeta = TimePageMeta(
  label: '未命名',
  icon: Icons.access_time,
);

TimePageMeta timePageMetaOf(String slug) =>
    kTimePageMeta[slug] ?? kFallbackTimePageMeta;

/// 按 slug 派生强调色。
///   - clock/fallback：sage（豁免家族）
///   - calendar：scheme.tertiary（蓝强调）
///   - metronome：scheme.outline（灰紫弱化）
Color colorFor(BuildContext context, String slug) {
  switch (slug) {
    case 'calendar':
      return Theme.of(context).colorScheme.tertiary;
    case 'metronome':
      return Theme.of(context).colorScheme.outline;
    default:
      return const Color(0xFFB5C9A3); // sage，豁免
  }
}