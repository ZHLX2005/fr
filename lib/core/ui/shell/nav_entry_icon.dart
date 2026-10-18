// NavEntry 图标统一渲染：demo 专属 SVG（Lab 图标集）优先，Material icon 兜底。
//
// 三个消费场景的着色约定：
//   底栏钉选条  —— tint = 选中态色（含未选中 42% 透明），强调点走主题自适应
//   设置页钉选  —— tint = onPrimaryContainer 主轮廓，强调点走主题自适应
//   ⋯ 溢出面板  —— tint = primary，强调点走主题自适应
//
// accent 不传时不再是「压成单色」——交给 [LabDemoIcon] 的自适应强调色
// （亮色主题过暗的 primary 自动提亮 / 深色主题轮廓自动压暗出对比），
// 这样 cobalt / zen 这类深 primary 主题在导航里也能看到醒目的强调点。
// 需要真单色（剪影）时显式传 accent: 与 tint 同色。
//
// entry.labIconAsset == null（核心入口 / 未登记 demo）→ 直接 Icon(entry.icon)。

import 'package:flutter/material.dart';

import '../../nav/nav_entry.dart';
import '../lab/lab_demo_icon.dart';

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

  /// Material icon 颜色；SVG 场景 = 主轮廓色（可带 alpha，未选中态用）。
  /// null 时 Material icon 走 IconTheme，SVG 主轮廓走主题自适应轮廓色。
  final Color? tint;

  /// SVG 强调点色。null → 主题自适应强调色（非单色化）；
  /// 传与 [tint] 相同的色 = 剪影单色。
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
      accentColor: accent,
      semanticsLabel: entry.title,
    );
  }
}
