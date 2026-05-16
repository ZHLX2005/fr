import 'package:flutter/material.dart';

/// 手电筒模块常量
class TorchConst {
  TorchConst._();

  // 颜色
  static const Color backgroundDark = Color(0xFF1C1C1E);
  static const Color cardDark = Color(0xFF2C2C2E);
  static const Color borderDark = Color(0xFF48484A);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color accentBlue = Color(0xFF0A84FF);
  static const Color accentGreen = Color(0xFF30D158);
  static const Color accentRed = Color(0xFFFF453A);
  static const Color accentYellow = Color(0xFFFFD60A);

  // 动画
  static const Duration modeSwitchDuration = Duration(milliseconds: 200);
  static const Duration pulseDuration = Duration(milliseconds: 1500);
  static const Duration controlsHideDelay = Duration(seconds: 3);
  static const Duration controlsFadeDuration = Duration(milliseconds: 400);

  // 亮度
  static const double minBrightness = 0.1;
  static const double maxBrightness = 1.0;
  static const double brightnessSwipeSensitivity = 200.0;
}

/// 护眼颜色预设
class EyeProtectionColors {
  EyeProtectionColors._();

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

  /// 预设颜色名称
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
