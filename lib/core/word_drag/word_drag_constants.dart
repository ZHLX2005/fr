// WordDrag 全局常量
//
// 所有跨组件共享的常量集中在此文件，避免同名常量分散在多处
// 修改时只需改一处，减少遗漏导致的 bug
//
// ## 常量使用一览
//
// ### ⚠️ 多文件共用常量（修改时必须同步检查）
// 这些常量在多个文件中被使用，修改时需确保两端值一致：
//
// | 常量 | 文件 | 用途 |
// |------|------|------|
// | `folderModeThreshold` | `draggable_word_card.dart`, `word_drag_page.dart` | 卡片下滑进入分类桶模式的阈值，必须相同 |
// | `swipeThreshold` | `draggable_word_card.dart` | 左右滑确认阈值，同时控制 Action Indicator 显示 |
// | `actionIndicatorThreshold` | `draggable_word_card.dart` | Action Indicator 亮起阈值，与 swipeThreshold 共用同一值 |
// | `actionIndicatorFolderThreshold` | `draggable_word_card.dart` | Action Indicator 文件夹模式阈值（>300 时显示 FOLDER） |
// | `stackScaleDecrement` | `draggable_word_card.dart` | 控制堆叠卡片的 scale 和 Y 偏移，两边必须同步 |
// | `stackYOffsetIncrement` | `draggable_word_card.dart` | 背景卡片堆叠 Y 偏移，与 scale 配合保持视觉一致 |
//
// ### 📦 category_drop_row.dart 专属
// | 常量 | 用途 |
// |------|------|
// | `bandPadding` | 垂直频道区域 padding |
// | `stickyRadius` | 粘附半径 |
// | `horizontalSwipeThreshold` | 水平滑动忽略阈值 |
/// | `edgeScrollThreshold` | 边缘滚动触发距离 |
/// | `minScrollSpeed` / `maxScrollSpeed` | 边缘滚动速度范围 |
/// | `bucketDefaultWidth` / `bucketActiveWidth` | 桶默认/激活宽度 |
/// | `bucketDefaultScale` / `bucketActiveScale` | 桶默认/激活 scale |
/// | `bucketDefaultLift` / `bucketActiveLift` | 桶默认/激活 lift（向上偏移） |
/// | `bucketScaleSpring` | 桶 scale 动画 spring |
/// | `bucketOtherSpring` | 桶 lift/width 动画 spring |
/// | `categoryRowHeight` | 分类桶行容器高度 |
/// | `categoryRowPaddingV` | 分类桶行垂直内边距 |
/// | `bucketSpacing` | 桶之间的间距 |
/// | `bucketIconSize` | 桶图标尺寸 |
/// | `bucketRadius` | 桶圆角 |
///
/// ### 🃏 draggable_word_card.dart 专属
/// | 常量 | 用途 |
/// |------|------|
/// | `flingThreshold` | 快速滑动速度阈值 |
/// | `cardSpringStiffness` / `cardSpringDampingRatio` | 卡片回弹 spring 参数 |
/// | `cardPressStiffness` / `cardPressDampingRatio` | 卡片按压 spring 参数 |
/// | `cardPressScale` | 卡片按压 scale 目标值 |
/// | `cardExitDuration` | 卡片退出动画时长（ms） |
/// | `cardSuckScale` | 吸入动画目标 scale |
/// | `cardSuckOffsetY` | 吸入动画下落距离 |
///
/// ### 📋 word_drag_page.dart 专属
/// | 常量 | 用途 |
/// |------|------|
/// | `drawerDuration` | 抽屉动画时长 |
/// | `drawerCollapsedHeight` | 抽屉折叠高度 |
/// | `actionLogExpandedHeight` | 操作日志抽屉展开高度 |
///
/// ## 设计原则
/// 1. **阈值类常量**（滑动、碰撞）在多文件间共用，修改后需两端验证
/// 2. **动画类常量**（spring 参数）在单文件内使用，保证内部一致性
/// 3. **尺寸类常量**（宽高、间距）在单文件内使用，方便整体缩放 UI

import 'dart:math';
import 'package:flutter/physics.dart';

class WordDragConstants {
  // ==================== ⚠️ 多文件共用阈值 ====================
  // 这些常量在多个 widget 中被使用，修改时必须同步检查引用处

  /// 滑动确认阈值 (px)
  /// 同时控制：左滑/右滑/上滑判定 + Action Indicator 亮起
  /// [draggable_word_card.dart] 用于 onSwipeLeft/Right/Up 判定
  static const double swipeThreshold = 160;

  /// 下滑进入分类桶模式阈值 (px)
  /// [draggable_word_card.dart] 卡片 offsetY > 此值时进入文件夹模式
  /// [word_drag_page.dart] 卡片 offsetY > 此值时显示 CategoryDropRow
  /// ⚠️ 两处必须保持相同值
  static const double folderModeThreshold = 200;

  /// 快速滑动速度阈值 (px/s)
  /// [draggable_word_card.dart] velocityY < -此值时触发快速上滑
  static const double flingThreshold = 800;

  /// Action Indicator 阈值 (px)
  /// [draggable_word_card.dart] _offsetX/Y > 此值时显示对应 Action Indicator
  /// 与 swipeThreshold 配合使用，控制提示图标显示
  static const double actionIndicatorThreshold = 100;

  /// Action Indicator 文件夹模式阈值 (px)
  /// [draggable_word_card.dart] _offsetY > 此值时显示 FOLDER 指示器
  static const double actionIndicatorFolderThreshold = 150;

  // ==================== 卡片堆叠参数 ====================
  // [draggable_word_card.dart] 控制背景卡片的视觉层次
  // ⚠️ stackScaleDecrement 和 stackYOffsetIncrement 配合使用
  // 确保 scale 递减和 Y 偏移同步变化

  /// 每层堆叠 scale 递减
  static const double stackScaleDecrement = 0.04;

  /// 每层堆叠 Y 偏移 (dp)
  static const double stackYOffsetIncrement = 15.0;

  // ==================== 📦 category_drop_row.dart 专属 ====================

  /// 垂直频道区域 padding (px)
  /// [category_drop_row.dart] 碰撞检测时允许的垂直偏差范围
  static const double bandPadding = 90;

  /// 粘附半径 (px)
  /// [category_drop_row.dart] 圆心距离 < 此值时触发粘附
  static const double stickyRadius = 280;

  /// 水平滑动忽略阈值 (px)
  /// [category_drop_row.dart] |offsetX| > 此值时忽略桶目标（防止横向滑动误触）
  static const double horizontalSwipeThreshold = 500;

  /// 边缘滚动触发距离 (px)
  /// [category_drop_row.dart] 卡片靠近边缘 < 此距离时触发自动滚动
  static const double edgeScrollThreshold = 100;

  /// 边缘滚动最小速度 (px/s)
  static const double minScrollSpeed = 6;

  /// 边缘滚动最大速度 (px/s)
  static const double maxScrollSpeed = 36;

  /// 桶默认宽度 (dp)
  static const double bucketDefaultWidth = 68;

  /// 桶激活宽度 (dp)
  static const double bucketActiveWidth = 88;

  /// 桶默认 scale
  static const double bucketDefaultScale = 0.82;

  /// 桶激活 scale
  static const double bucketActiveScale = 1.2;

  /// 桶默认 lift (dp, 向上为负)
  static const double bucketDefaultLift = 0;

  /// 桶激活 lift (dp, 向上偏移)
  static const double bucketActiveLift = -8;

  /// 桶 scale 动画 spring (dampingRatio=0.6)
  /// [category_drop_row.dart] _BucketItem 激活动画
  static final SpringDescription bucketScaleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.6 * 2 * sqrt(320.0),
  );

  /// 桶 lift/width 动画 spring (dampingRatio=0.7)
  /// [category_drop_row.dart] _BucketItem 激活动画
  static final SpringDescription bucketOtherSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.7 * 2 * sqrt(320.0),
  );

  /// 分类桶行容器高度 (dp)
  /// [category_drop_row.dart] 需足够容纳激活桶的 scale 1.2 + lift -8 的显示
  static const double categoryRowHeight = 140.0;

  /// 分类桶行垂直内边距 (dp)
  static const double categoryRowPaddingV = 14.0;

  /// 桶间距 (dp)
  static const double bucketSpacing = 8.0;

  /// 桶图标尺寸 (dp)
  static const double bucketIconSize = 64.0;

  /// 桶圆角 (dp)
  static const double bucketRadius = 16.0;

  // ==================== 🃏 draggable_word_card.dart 专属 ====================

  /// 卡片 Spring 回弹 stiffness
  /// [draggable_word_card.dart] _animateSpringBack 使用的 spring 刚度
  static const double cardSpringStiffness = 2000.0;

  /// 卡片 Spring 回弹 dampingRatio
  /// [draggable_word_card.dart] 与 stiffness 配合计算阻尼
  static const double cardSpringDampingRatio = 0.85;

  /// 卡片按压 scale 目标值
  /// [draggable_word_card.dart] 按下时缩到 0.96
  static const double cardPressScale = 0.96;

  /// 卡片按压 spring stiffness
  /// [draggable_word_card.dart] onPanStart 按压缩放动画
  static const double cardPressStiffness = 500.0;

  /// 卡片按压 spring dampingRatio
  /// [draggable_word_card.dart] 与 stiffness 配合计算阻尼
  static const double cardPressDampingRatio = 0.6;

  /// 卡片退出动画时长 (ms)
  /// [draggable_word_card.dart] _animateSwipeOut / _animateSuckIntoFolder
  static const int cardExitDuration = 250;

  /// 吸入动画目标 scale
  /// [draggable_word_card.dart] _animateSuckIntoFolder 缩到 0.1
  static const double cardSuckScale = 0.1;

  /// 吸入动画卡片下落距离 (dp)
  /// [draggable_word_card.dart] _animateSuckIntoFolder Y 方向额外偏移
  static const double cardSuckOffsetY = 200;

  // ==================== 📋 word_drag_page.dart 专属 ====================

  /// 抽屉展开/收起动画时长 (ms)
  /// [word_drag_page.dart] _ActionLogDrawer / _WordListDrawer 动画
  static const int drawerDuration = 300;

  /// 抽屉折叠高度 (dp)
  static const double drawerCollapsedHeight = 60.0;

  /// 操作日志抽屉展开高度 (dp)
  static const double actionLogExpandedHeight = 280.0;
}
