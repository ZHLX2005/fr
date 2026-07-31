// 时间页（timePage）展示元数据 —— 对应 game_center 的 kGameMeta。
//
// 同样的取舍：常量层不 import 任何 demo 实现文件，按 demo.slug 查。
// 添加新时间页三步：
//   ① 让 demo `override bool get timePage => true;`
//   ② 在 [kTimePageMeta] 里按 slug 加一条
//   ③ 若引入新排序规则，更新 [FocusHomePage] 的 featured 选择
//
// icon/color 与现有 focus 莫兰迪卡一致（sage 渐变主基调）。
import 'package:flutter/material.dart';

/// 单个 timePage demo 的展示元数据。
class TimePageMeta {
  const TimePageMeta({
    required this.label,
    required this.icon,
    required this.color,
    this.featured = false,
  });

  /// 覆盖 [DemoPage.title]（如 'Clock' → '时钟'），统一中文。
  final String label;

  /// 卡片主图标。
  final IconData icon;

  /// 卡片强调色（取自 focus 莫兰迪调色板，与现有卡片风格对齐）。
  final Color color;

  /// true → 占 Focus 主页的精选大卡（一张）。目前只有 clock。
  final bool featured;
}

/// slug → 展示元数据。key 必须与 [DemoPage.slug] 完全一致。
const Map<String, TimePageMeta> kTimePageMeta = {
  'clock': TimePageMeta(
    label: '时钟',
    icon: Icons.access_time_rounded,
    color: Color(0xFFB5C9A3), // sage，与今日专注卡同色系
    featured: true,
  ),
  'calendar': TimePageMeta(
    label: '日历',
    icon: Icons.calendar_month_outlined,
    color: Color(0xFF6B9DFC),
  ),
  'metronome': TimePageMeta(
    label: '节拍器',
    icon: Icons.music_note_outlined,
    color: Color(0xFFB39EB5),
  ),
};

/// 未登记 slug 的兜底元数据（防御性：避免 UI 上 null 字段）。
const TimePageMeta kFallbackTimePageMeta = TimePageMeta(
  label: '未命名',
  icon: Icons.access_time,
  color: Color(0xFFB5C9A3),
);

TimePageMeta timePageMetaOf(String slug) =>
    kTimePageMeta[slug] ?? kFallbackTimePageMeta;