/// 手电筒模块常量 — 仅动画时长与亮度参数。
///
/// UI 颜色（背景/边框/按钮/文本）已迁移到 `BoardTheme.of(context)` token。
/// 护眼颜色预设由 `context.gameColors.protectPresets` / `protectPresetNames`
/// 从 ColorScheme 派生（之前这里是 const Color 自我豁免清单 → 零硬编码）。
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
}
