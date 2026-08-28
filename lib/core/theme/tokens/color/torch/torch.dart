// Layer 1 — 灯具护眼色常量（从 ColorScheme 派生，跟主题）。

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
  static Color protectCoolWhite(ColorScheme scheme) => scheme.surfaceContainerHighest;

  /// 10 种护眼色预设
  static List<Color> protectPresets(ColorScheme scheme) {
    final c = scheme;
    return [
      c.tertiary,
      Color.lerp(c.tertiary, c.error, 0.3)!,
      Color.lerp(c.tertiaryContainer, c.tertiary, 0.5)!,
      Color.lerp(c.tertiaryContainer, c.onSurface, 0.4)!,
      Color.lerp(c.tertiary, c.onSurface, 0.55)!,
      Color.lerp(c.primary, c.tertiary, 0.5)!,
      Color.lerp(c.primary, c.tertiary, 0.25)!,
      Color.lerp(c.tertiary, c.error, 0.4)!,
      Color.lerp(c.tertiary, c.onSurface, 0.3)!,
      Color.lerp(c.onSurface, c.primary, 0.5)!,
    ];
  }

  /// 10 种护眼色名称
  static const List<String> protectPresetNames = [
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