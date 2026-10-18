import 'package:flutter/material.dart';

/// 手电筒模块常量 — 仅动画时长与亮度参数。
///
/// UI 颜色（背景/边框/按钮/文本）走 `ColorScheme` / theme token。
/// 护眼预设色是补光实际输出色（主题豁免），单一来源在
/// `lib/design_tokens/color/torch.dart` 的 `TorchColors.presets`。
class TorchConst {
  TorchConst._();

  // 动画
  static const Duration modeSwitchDuration = Duration(milliseconds: 200);
  static const Duration pulseDuration = Duration(milliseconds: 1500);
  static const Duration controlsHideDelay = Duration(seconds: 3);
  static const Duration controlsFadeDuration = Duration(milliseconds: 400);

  // 亮度
  static const double minBrightness = 0.1;
  static const double maxBrightness = 1.0;
  static const double brightnessSwipeSensitivity = 200.0;

  /// 色相环可视半径外的额外触控边距，便于环外拖动跟手
  static const double hueRingHitPadding = 36.0;
}
