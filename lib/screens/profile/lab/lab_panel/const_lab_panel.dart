// Lab 容器（demo 网格 + 下拉收藏面板）的模块常量。
//
// 收口原则：**会被调参的视觉量**（色、圆角、时长、网格参数、alpha、尺寸）
// 统一放这里；只在一处出现且无调参意义的布局微调（个别 SizedBox 间距）留在原地。

import 'package:flutter/material.dart';

// Lab 容器（demo 网格 + 下拉收藏面板）的模块常量。
//
// 收口原则：**会被调参的视觉量**（色、圆角、时长、网格参数、alpha、尺寸）
// 统一放这里；只在一处出现且无调参意义的布局微调（个别 SizedBox 间距）留在原地。
//
// 分组与文件对应：
//   _Grid    → components.dart 的 demo 网格与卡片
//   _Reveal  → 入场动画（components.dart / 收藏格子共用）
//   _Panel   → panel_content.dart 的面板内容、标题条、空态
//   _Delete  → panel_content.dart 的拖拽删除区
//   _Handle  → panel_content.dart 的把手与状态圈
//   _Sheet   → components.dart 的背景设置 sheet

// ── demo 网格 / 卡片 ────────────────────────────────────────────
const double kLabGridPadding = 16.0;
const int kLabGridCrossAxisCount = 2;
const double kLabGridSpacing = 16.0;
const double kLabGridAspectRatio = 1.1;

/// 卡片按下缩放
const double kLabCardPressScale = 0.97;
const Duration kLabCardPressDuration = Duration(milliseconds: 100);
const double kLabCardPadding = 16.0;

/// 卡片自定义背景图上的压暗蒙版（顶 → 底）
const double kLabCardScrimTopAlpha = 0.3;
const double kLabCardScrimBottomAlpha = 0.6;

// ── 入场动画 ────────────────────────────────────────────────────
const Duration kLabRevealDuration = Duration(milliseconds: 1200);

/// 第 n 项的起始延迟 = index * step，封顶 maxDelay（单位：controller 进度 0~1）
const double kLabRevealDelayStep = 0.06;
const double kLabRevealMaxDelay = 0.72;
const double kLabRevealItemDuration = 0.28;
const double kLabRevealTranslateY = 24.0;

// ── 面板内容 ────────────────────────────────────────────────────
const EdgeInsets kLabPanelListPadding = EdgeInsets.fromLTRB(18, 24, 18, 18);

/// 面板整体随 progress 的入场：位移与缩放的起点
const double kLabPanelContentOffset = 16.0;
const double kLabPanelContentMinScale = 0.5;

/// 玻璃容器（标题条 / 空态卡）
const double kLabPanelGlassRadius = 24.0;
const double kLabPanelGlassShadowAlpha = 0.08;
const double kLabPanelGlassShadowBlur = 24.0;
const Offset kLabPanelGlassShadowOffset = Offset(0, 10);

/// 强调色浅底（icon 容器 / pill）统一 alpha
const double kLabPanelAccentSoftAlpha = 0.16;

/// 收藏快捷格子
const int kLabFavoriteCrossAxisCount = 4;
const double kLabFavoriteSpacing = 8.0;
const double kLabFavoriteAspectRatio = 0.92;
const double kLabFavoriteRadius = 16.0;
const double kLabFavoriteIconBoxSize = 34.0;
const double kLabFavoriteIconBoxRadius = 12.0;
const double kLabFavoriteIconSize = 18.0;

/// 按下 / 拖拽中的覆盖层
const double kLabFavoritePressOverlayAlpha = 0.06;
const Duration kLabFavoriteLongPressDelay = Duration(milliseconds: 300);

/// 空态卡里的大 icon 容器
const double kLabEmptyIconBoxSize = 52.0;
const double kLabEmptyIconBoxRadius = 16.0;
const double kLabEmptyIconSize = 26.0;

// ── 拖拽删除区 ──────────────────────────────────────────────────
/// 删除按钮 active 状态固定红（scheme.error 已统一为红族，跨主题保持破坏性语义）。
const Color kLabDeleteActiveColor = Color(0xFFD63B3B); // 历史参考，build 时改用 scheme.error
const Color kLabDeleteIdleColor = Color(0xFFEF6B6B);     // 同上，build 时改用 scheme.error + alpha
const double kLabDeleteIdleAlpha = 0.92;
const Color kLabDeleteShadowColor = Color(0xFFB3261E);  // 同上，build 时改用 scheme.errorContainer

// ★ 迁移说明：以下 3 个 const Color 字段保留作历史参考常量，实际使用点已迁到
//   `Theme.of(context).colorScheme.error` / `.errorContainer` 派生（lab_panel_content.dart
//   builder 内）。后续可移除。

const double kLabDeleteRadius = 24.0;
const double kLabDeleteMinHeight = 76.0;
const Duration kLabDeleteAnimDuration = Duration(milliseconds: 140);
const EdgeInsets kLabDeletePadding = EdgeInsets.symmetric(
  horizontal: 18,
  vertical: 14,
);

// ── 把手 / 状态圈 ───────────────────────────────────────────────
const Duration kLabHandleAnimDuration = Duration(milliseconds: 120);

/// 把手宽 = base + progress * gain - closeProgress * shrink，再夹到 [min, max]
const double kLabHandleWidthBase = 40.0;
const double kLabHandleWidthGain = 18.0;
const double kLabHandleWidthShrink = 8.0;
const double kLabHandleWidthMin = 30.0;
const double kLabHandleWidthMax = 58.0;

const double kLabHandleHeightBase = 4.0;
const double kLabHandleHeightGain = 2.0;
const double kLabHandleHeightMax = 6.0;

/// 状态圈画布尺寸
const double kLabHandleRingSize = 42.0;

// ── 背景设置 sheet ──────────────────────────────────────────────
/// sheet 占屏高比例
const double kLabSheetHeightFactor = 0.75;
const double kLabSheetPadding = 16.0;
