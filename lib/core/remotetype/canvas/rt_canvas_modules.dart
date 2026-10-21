// lib/core/remotetype/canvas/rt_canvas_modules.dart
//
// 画布模块登记表 —— 模块的单一事实源：模块设置页（设置页样式：图标 + 名称 +
// 说明 + 开关）与编辑态 chip 行都从这里取，避免两处两套清单。
//
// 另收三个纯函数，供设置页与画布共用（范围 / 缺省规格 / 位置档位）：
//   · rtCanvasModuleRange      —— 尺寸限位（画布缩放与设置页档位同一口径）
//   · rtCanvasModuleDefaults   —— 未指定宽高时的兜底规格
//   · rtCanvasGridAnchor       —— 九宫格位置预设
//   · rtCanvasSizeStep         —— 小/标准/大三档尺寸
// 规则改动须同步单测（rt_canvas_layout_test.dart）。

import 'dart:math' as math;

import 'package:flutter/material.dart' show IconData, Icons;

import '../data/rt_prefs.dart'
    show
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleComposer,
        kRtCanvasModuleDpad,
        kRtCanvasModuleInput,
        kRtCanvasModuleStickL,
        kRtCanvasModuleStickR,
        kRtCanvasModuleKb,
        kRtCanvasModuleTouchpad,
        kRtCanvasModuleVpad,
        kRtCanvasPadDefH,
        kRtCanvasPadDefW;

/// 模块登记项（设置页一行的全部信息）。
class RtCanvasModuleSpec {
  const RtCanvasModuleSpec({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    this.fullscreen = false,
    this.locksLandscape = false,
  });

  final String id;

  /// 设置页条目标题（口语用途，与布局预设命名同风格）。
  final String name;

  /// 一句话说明用途（设置页副标题）。
  final String desc;
  final IconData icon;

  /// 全屏模块（触控屏）：位置/尺寸不可编排，设置页里相应入口置灰。
  final bool fullscreen;

  /// 锁定横屏（轮盘 / 手柄 / 键盘）：竖屏不可用，需旋转。
  final bool locksLandscape;
}

/// 模块登记表（设置页与 chip 行的展示顺序：打字类 → 指针类 → 手柄类）。
const List<RtCanvasModuleSpec> kRtCanvasModuleSpecs = [
  RtCanvasModuleSpec(
    id: kRtCanvasModuleComposer,
    name: '输入页',
    desc: '工具行 + 快捷键托盘 + 输入框（连接后落到的打字页）',
    icon: Icons.article_outlined,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleInput,
    name: '输入框',
    desc: '一行输入框，全文同步到电脑',
    icon: Icons.keyboard_alt_outlined,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleKb,
    name: '键盘',
    desc: '全键盘，按键即发到电脑（Fn 行可展开）',
    icon: Icons.keyboard_outlined,
    locksLandscape: true,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleTouchpad,
    name: '触摸板',
    desc: '拖动 = 光标 · 双指 = 滚轮 · 点按 = 左键',
    icon: Icons.mouse_outlined,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleStickL,
    name: '左摇杆',
    desc: '模拟摇杆（左）：拖动出斜向走位，接电脑虚拟手柄',
    icon: Icons.videogame_asset_outlined,
    locksLandscape: true,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleStickR,
    name: '右摇杆',
    desc: '模拟摇杆（右）：视角 / 瞄准，接电脑虚拟手柄',
    icon: Icons.videogame_asset,
    locksLandscape: true,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleDpad,
    name: '轮盘',
    desc: '方向轮盘，接电脑虚拟手柄十字键',
    icon: Icons.gamepad_outlined,
    locksLandscape: true,
  ),
  RtCanvasModuleSpec(
    id: kRtCanvasModuleVpad,
    name: '手柄',
    desc: 'ABXY + 肩键扳机，接电脑虚拟手柄',
    icon: Icons.sports_esports_outlined,
    locksLandscape: true,
  ),
];

RtCanvasModuleSpec? rtCanvasModuleSpec(String id) {
  for (final s in kRtCanvasModuleSpecs) {
    if (s.id == id) return s;
  }
  return null;
}

/// 模块尺寸限位（wMin, wMax, hMin, hMax，归一化）。轮盘恒以正方形渲染
/// （取宽高像素较小者），范围即正方形的两轴限位。
(double, double, double, double) rtCanvasModuleRange(String id) => switch (id) {
  kRtCanvasModuleTouchpad => (0.25, 1.0, 0.35, 1.0),
  kRtCanvasModuleDpad => (0.12, 0.65, 0.12, 0.85),
  kRtCanvasModuleVpad => (0.25, 0.70, 0.35, 1.0),
  kRtCanvasModuleKb => (0.40, 1.0, 0.30, 1.0),
  kRtCanvasModuleComposer => (0.40, 1.0, 0.30, 1.0),
  _ => (0.20, 1.0, 0.08, 0.40),
};

/// 未指定宽高时的兜底规格（内置预设 / 画布渲染 / 设置页档位 / 缩略图
/// 四处共用的单一事实源）。
(double, double) rtCanvasModuleDefaults(String id) => switch (id) {
  kRtCanvasModuleDpad => (0.22, 0.52),
  kRtCanvasModuleVpad => (0.36, 0.70),
  kRtCanvasModuleKb => (0.94, 0.82),
  kRtCanvasModuleComposer => (0.96, 0.92),
  kRtCanvasModuleTouchpad => (kRtCanvasPadDefW, kRtCanvasPadDefH),
  _ => (kRtCanvasInputDefW, kRtCanvasInputDefH),
};

/// 九宫格位置预设：列 / 行各取 0..2（左上 → 右下）。返回归一化中心锚点。
Offset2D rtCanvasGridAnchor(int col, int row) {
  const xs = [0.25, 0.50, 0.75];
  const ys = [0.25, 0.50, 0.75];
  return Offset2D(xs[col.clamp(0, 2)], ys[row.clamp(0, 2)]);
}

/// 归一化二维点（不依赖 Flutter 的 Offset，便于纯函数单测）。
class Offset2D {
  const Offset2D(this.x, this.y);
  final double x;
  final double y;
}

/// 尺寸档位：以模块缺省规格为基准的倍率（设置页「小 / 标准 / 大」）。
const List<double> kRtCanvasSizeSteps = [0.8, 1.0, 1.3];

/// 取第 [step] 档尺寸（越界钳到档位范围内），并钳回模块限位。
(double, double) rtCanvasSizeStep(String id, int step) {
  final factor =
      kRtCanvasSizeSteps[step.clamp(0, kRtCanvasSizeSteps.length - 1)];
  final (dw, dh) = rtCanvasModuleDefaults(id);
  final (wMin, wMax, hMin, hMax) = rtCanvasModuleRange(id);
  return (
    math.min(math.max(dw * factor, wMin), wMax),
    math.min(math.max(dh * factor, hMin), hMax),
  );
}
