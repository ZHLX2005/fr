// NavEntry 图标统一渲染：demo 专属 SVG（Lab 图标集）优先，Material icon 兜底。
//
// 三个消费场景的着色约定：
//   底栏钉选条  —— 单色：tint = 选中色（primary / primary@42%），双色压成单色
//   设置页钉选  —— 双色：tint = onPrimaryContainer 主轮廓 + accent = 主题强调点
//   ⋯ 溢出面板  —— 单色：tint = primary（沿用原有单色图标观感）
//
// entry.labIconAsset == null（核心入口 / 未登记 demo）→ 直接 Icon(entry.icon)。

import 'package:flutter/material.dart';

import '../core/nav/nav_entry.dart';
import 'lab_demo_icon.dart';

class NavEntryIcon extends StatelessWidget {
  const NavEntryIcon({
    super.key,
    required this.entry,
    this.size = 18,
    this.tint,
    this.accent,
  });

  final NavEntry entry;
  final double size;

  /// Material icon 颜色；SVG 场景 = 主轮廓色。
  /// null 时 Material icon 走 IconTheme，SVG 主轮廓走主题 text。
  final Color? tint;

  /// 非 null 时 SVG 保持双色：[tint] 主轮廓 + [accent] 强调点。
  /// null 时 SVG 压成 tint 单色（强调点同色）。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final asset = entry.labIconAsset;
    if (asset == null) {
      return Icon(entry.icon, size: size, color: tint);
    }
    return LabDemoIcon(
      assetBaseName: asset,
      size: size,
      inkColor: tint,
      accentColor: accent ?? tint,
      semanticsLabel: entry.title,
    );
  }
}
