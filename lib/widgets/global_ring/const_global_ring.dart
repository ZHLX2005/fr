// 全局圆环常量。
//
// 圆环 = 常驻在所有页面之上的一个环形入口，点击弹 KV 清单提交面板。

import 'dart:math' show exp, cos;

import 'package:flutter/animation.dart';

/// 全局圆环常量
class ConstGlobalRing {
  ConstGlobalRing._();

  /// 圆环外径
  static const double size = 56;

  /// 环宽（描边）
  static const double borderWidth = 3;

  /// 圆环中心图标尺寸
  static const double iconSize = 22;

  /// 距屏幕左右 / 上边缘的最小间距
  static const double margin = 12;

  /// 底部避让高度：MainScreen 的 XiaoDouZiBottomBar 高 64
  /// （lib/widgets/xiaodouzi_bottom_bar.dart 的 _barHeight）。
  /// 圆环常驻在 Navigator 之上，不止覆盖 tab 页也覆盖全屏路由，
  /// 所以这里恒留出这一段——宁可圆环少占一条底带，也不能压住 tab 按钮。
  static const double bottomBarHeight = 64;

  /// 吸附动画时长。短到"眨一下眼就到位"，不做持续动效。
  static const Duration snapDuration = Duration(milliseconds: 300);

  /// 位置持久化 key（存归一化比例，换设备/转屏后仍落在同一相对位置）
  static const String prefPosX = 'global_ring_x';
  static const String prefPosY = 'global_ring_y';

  /// 开关持久化 key。设置在 KV 清单页（见 kvcli_todo_demo 的圆环开关行）。
  static const String prefEnabled = 'global_ring_enabled';

  /// 未持久化过时的默认开关态 —— 特性默认开启，不想要就去 KV 清单页关掉。
  static const bool defaultEnabled = true;

  /// 未持久化过时的默认落位（右下角，避让底部栏）
  static const double defaultNormX = 1.0;
  static const double defaultNormY = 0.72;
}

/// 吸附回弹曲线 —— 指数衰减余弦震荡。
///
/// 与 `lib/widgets/xiaodouzi_bottom_bar.dart` 的 `_QQCurve` 同一公式；
/// 那个类是文件私有的，未提升为公共 curve，这里按同公式复刻以保持
/// 圆环与底部栏的动效手感一致。
class RingSnapCurve extends Curve {
  const RingSnapCurve();

  @override
  double transform(double t) => 1 - exp(-4.5 * t) * cos(9.425 * t);
}
