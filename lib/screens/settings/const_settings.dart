// 设置页（钉选快捷区 + 钉选管理弹窗）模块常量。
//
// 收口原则同 const_lab_panel：会被调参的视觉量统一放这里。

import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/entities/reorderable_animation_config.dart';

// ── 快捷格子（主页面钉选区 / 管理弹窗共用一套网格参数） ─────────
const int kSettingsCellCrossAxisCount = 4;
const double kSettingsCellSpacing = 10.0;
const double kSettingsCellAspectRatio = 1.0;
const double kSettingsCellRadius = 16.0;
const double kSettingsCellIconBoxSize = 36.0;
const double kSettingsCellIconBoxRadius = 12.0;
const double kSettingsCellIconSize = 18.0;
const double kSettingsCellLabelSize = 10.0;

// ── 拖拽动效 ────────────────────────────────────────────────────
// 源头是 lab 收藏面板的拖拽手感；这里沿用 ⋯ 溢出面板调好的「iOS q 弹感」
// 四件套（曲线全部 easeOutBack，过冲 ~10% 再收敛）：拾起 200ms 弹到 1.10、
// 邻居让位 280ms 过冲、落位 360ms 飞回槽位、提交重排 260ms 兜底。
const Duration kSettingsDragLongPressDelay = Duration(milliseconds: 200);
const double kSettingsDragFeedbackScale = 1.10;
const ReorderableAnimationConfig kSettingsDragConfig =
    ReorderableAnimationConfig(
      dragFeedbackDuration: Duration(milliseconds: 200),
      dragFeedbackCurve: Curves.easeOutBack,
      draggingPositionChangeDuration: Duration(milliseconds: 280),
      draggingPositionChangeCurve: Curves.easeOutBack,
      releasedItemDuration: Duration(milliseconds: 360),
      releasedItemCurve: Curves.easeOutBack,
      positionChangeDuration: Duration(milliseconds: 260),
      positionChangeCurve: Curves.easeOutBack,
    );

/// 拖起格子的浮起阴影（明底 surface 需要浮起感；lab 暗底面板是关阴影的）。
BoxDecoration settingsDragChildDecoration(Color onSurface) => BoxDecoration(
  color: onSurface.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(kSettingsCellRadius),
  boxShadow: const [
    BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 10)),
  ],
);

// ── 钉选管理弹窗 ────────────────────────────────────────────────
const double kSettingsSheetRadius = 28.0;
const double kSettingsSheetBarrierAlpha = 0.28;

/// 弹窗目标高度占屏比；键盘弹出时自动收窄（见 pin_editor_sheet）。
const double kSettingsSheetHeightFactor = 0.85;
