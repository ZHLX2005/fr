/// WordDrag 全局常量
///
/// 所有跨组件共享的常量集中在此文件，避免同名常量分散在多处
/// 修改时只需改一处，减少遗漏导致的 bug

import 'package:flutter/physics.dart';

/// 卡片滑动阈值
class WordDragConstants {
  // ==================== 滑动阈值 ====================

  /// 滑动确认阈值 (px)
  static const double swipeThreshold = 160;

  /// 下滑进入分类桶模式阈值 (px)
  static const double folderModeThreshold = 300;

  /// 快速滑动速度阈值 (px/s)
  static const double flingThreshold = 800;

  /// Action Indicator 阈值 (px)
  static const double actionIndicatorThreshold = 100;

  /// Action Indicator 文件夹模式阈值 (px)
  static const double actionIndicatorFolderThreshold = 150;

  // ==================== 桶碰撞检测 ====================

  /// 垂直频道区域 padding (px)
  static const double bandPadding = 90;

  /// 粘附半径 (px) - 圆心距离小于此值时粘附
  static const double stickyRadius = 280;

  /// 水平滑动忽略阈值 (px) - |offsetX| > 此值时忽略桶目标
  static const double horizontalSwipeThreshold = 500;

  // ==================== 边缘滚动 ====================

  /// 边缘滚动触发距离 (px)
  static const double edgeScrollThreshold = 100;

  /// 边缘滚动最小速度 (px/s)
  static const double minScrollSpeed = 6;

  /// 边缘滚动最大速度 (px/s)
  static const double maxScrollSpeed = 36;

  // ==================== 桶动画参数 ====================

  /// 桶默认宽度 (dp)
  static const double bucketDefaultWidth = 68;

  /// 桶激活宽度 (dp)
  static const double bucketActiveWidth = 88;

  /// 桶默认 scale
  static const double bucketDefaultScale = 0.82;

  /// 桶激活 scale
  static const double bucketActiveScale = 1.2;

  /// 桶默认 lift (dp)
  static const double bucketDefaultLift = 0;

  /// 桶激活 lift (dp, 向上)
  static const double bucketActiveLift = -8;

  /// 桶激活 scale spring 参数
  static final SpringDescription bucketScaleSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.6 * 2 * 17.888 * 1.0, // dampingRatio=0.6
  );

  /// 桶 lift/width spring 参数
  static final SpringDescription bucketOtherSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.7 * 2 * 17.888 * 1.0, // dampingRatio=0.7
  );

  // ==================== 卡片动画参数 ====================

  /// 卡片 Spring 回弹 stiffness
  static const double cardSpringStiffness = 2000.0;

  /// 卡片 Spring 回弹 dampingRatio
  static const double cardSpringDampingRatio = 0.85;

  /// 卡片按压 scale 目标值
  static const double cardPressScale = 0.96;

  /// 卡片按压 spring stiffness
  static const double cardPressStiffness = 500.0;

  /// 卡片按压 spring dampingRatio
  static const double cardPressDampingRatio = 0.6;

  /// 卡片退出动画时长 (ms)
  static const int cardExitDuration = 250;

  /// 吸入动画目标 scale
  static const double cardSuckScale = 0.1;

  /// 吸入动画卡片下移距离 (dp)
  static const double cardSuckOffsetY = 200;

  // ==================== 卡片堆叠参数 ====================

  /// 每层堆叠 scale 递减
  static const double stackScaleDecrement = 0.04;

  /// 每层堆叠 Y 偏移 (dp)
  static const double stackYOffsetIncrement = 15.0;

  // ==================== 动画时长 ====================

  /// 抽屉展开时长 (ms)
  static const int drawerDuration = 300;

  /// 抽屉折叠高度 (dp)
  static const double drawerCollapsedHeight = 60.0;

  /// 单词列表抽屉展开高度 (dp)
  static const double wordListExpandedHeight = 200.0;

  /// 操作日志抽屉展开高度 (dp)
  static const double actionLogExpandedHeight = 280.0;

  /// 分类桶行高度 (dp)
  static const double categoryRowHeight = 140.0;

  /// 分类桶行 padding vertical (dp)
  static const double categoryRowPaddingV = 14.0;

  /// 桶间距 (dp)
  static const double bucketSpacing = 8.0;

  /// 桶图标尺寸 (dp)
  static const double bucketIconSize = 64.0;

  /// 桶圆角 (dp)
  static const double bucketRadius = 16.0;
}
