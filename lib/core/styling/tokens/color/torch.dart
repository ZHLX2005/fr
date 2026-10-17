// Layer 1 — 灯具护眼色常量。
//
// 4 个环境保护色仍从 ColorScheme 派生；
// 10 种补光预设为实际输出色（主题豁免），固定 hex，不随主题漂移。

import 'package:flutter/material.dart';

class TorchColors {
  TorchColors._();

  /// 暖黄 —— Color.lerp(scheme.tertiary, scheme.tertiaryContainer, 0.5)
  static Color protectWarmYellow(ColorScheme scheme) =>
      Color.lerp(scheme.tertiary, scheme.tertiaryContainer, 0.5)!;

  /// 暖橙 —— scheme.tertiary
  static Color protectWarmOrange(ColorScheme scheme) => scheme.tertiary;

  /// 中性 —— scheme.onSurface @ 60% alpha
  static Color protectNeutral(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: 0.6);

  /// 冷白 —— scheme.surfaceContainerHighest
  static Color protectCoolWhite(ColorScheme scheme) =>
      scheme.surfaceContainerHighest;

  // ─── 10 种护眼色预设（主题豁免：屏幕补光实际输出色，const 单一来源）───
  //
  // lab torch_demo 直接消费本表（2026-10 起单一来源，不再手工同步 lab 副本）。
  // 注意区分：下面的 const 预设（warmYellow 等）是补光输出色；
  // 上面的 protectWarmYellow(scheme) 等派生方法是 UI 环境角色，两套互不相干。

  /// 经典护眼黄
  static const Color warmYellow = Color(0xFFFFE066);

  /// 琥珀色
  static const Color amber = Color(0xFFFFBF00);

  /// 暖白色
  static const Color warmWhite = Color(0xFFFFF8E7);

  /// 羊皮纸
  static const Color sepia = Color(0xFFF5DEB3);

  /// 暗琥珀
  static const Color darkAmber = Color(0xFFCC9900);

  /// 墨绿色
  static const Color darkGreen = Color(0xFF2E8B57);

  /// 暗青色
  static const Color darkCyan = Color(0xFF008B8B);

  /// 珊瑚橙
  static const Color coral = Color(0xFFFF7F50);

  /// 玫瑰棕
  static const Color rosyBrown = Color(0xFFBC8F8F);

  /// 午夜蓝
  static const Color midnightBlue = Color(0xFF191970);

  /// 所有预设颜色列表
  static const List<Color> presets = [
    warmYellow,
    amber,
    warmWhite,
    sepia,
    darkAmber,
    darkGreen,
    darkCyan,
    coral,
    rosyBrown,
    midnightBlue,
  ];

  /// 10 种护眼色名称（与 [presets] 一一对应）
  static const List<String> presetNames = [
    '护眼黄',
    '琥珀',
    '暖白',
    '羊皮纸',
    '暗琥珀',
    '墨绿',
    '暗青',
    '珊瑚',
    '玫瑰棕',
    '午夜蓝',
  ];
}
