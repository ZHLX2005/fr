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

  /// 10 种护眼色预设（主题豁免：屏幕补光实际输出色）
  ///
  /// 与 lab `EyeProtectionColors.presets` 保持一致。
  static List<Color> protectPresets(ColorScheme scheme) => const [
        Color(0xFFFFE066), // 护眼黄
        Color(0xFFFFBF00), // 琥珀
        Color(0xFFFFF8E7), // 暖白
        Color(0xFFF5DEB3), // 羊皮纸
        Color(0xFFCC9900), // 暗琥珀
        Color(0xFF2E8B57), // 墨绿
        Color(0xFF008B8B), // 暗青
        Color(0xFFFF7F50), // 珊瑚
        Color(0xFFBC8F8F), // 玫瑰棕
        Color(0xFF191970), // 午夜蓝
      ];

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
