// Layer 3: Game Colors Strategy 契约。
//
// 棋盘/角色/护眼色 — 之前是 top-level const Map/Field（自我豁免硬编码）。
// 现在统一为 ThemeExtension 注入，从 ColorScheme 派生。
//
// 角色：
//   pieceColors     — 7 种（俄罗斯方块 7 方块色）
//   avatarColors    — 6 种（团队卡 6 角色头像色）
//   pieceBlack/White — 五子棋本黑/本白
//   protectPalette  — 4 种护眼色（torch 灯具 demo 用户选择）

import 'package:flutter/material.dart';

@immutable
abstract class GameColorsStrategy {
  const GameColorsStrategy();

  /// 7 种方块色（tetris 7 方块）—— 跨主题保持视觉区分
  List<Color> get pieceColors;

  /// 6 种头像色（team_card 6 角色）
  List<Color> get avatarColors;

  /// 五子棋本黑（本方）
  Color get pieceBlack;

  /// 五子棋本白（客方）
  Color get pieceWhite;

  /// 4 种护眼色（torch 灯具）—— 暖黄/暖橙/中性/冷白
  Color get protectWarmYellow;
  Color get protectWarmOrange;
  Color get protectNeutral;
  Color get protectCoolWhite;

  /// 10 种护眼色预设（torch 灯具选择）—— 由 ColorScheme 派生
  List<Color> get protectPresets;

  /// 10 种护眼色名称（与 protectPresets 一一对应）
  List<String> get protectPresetNames;

  /// 完整 ColorScheme 兜底
  ColorScheme get scheme;
}

/// 默认 GameColorsStrategy：从 ColorScheme 派生所有 game 颜色。
///
/// 7 种方块色用 Color.lerp(primary ↔ tertiary, t) + error 派生，
/// 保证跨主题都有可读对比 + 主题辨识度。
class DefaultGameColorsStrategy extends GameColorsStrategy {
  @override
  final ColorScheme scheme;

  static DefaultGameColorsStrategy? _cached;

  factory DefaultGameColorsStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultGameColorsStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  const DefaultGameColorsStrategy._(this.scheme);

  @override
  List<Color> get pieceColors {
    final c = scheme;
    return [
      c.primary,
      Color.lerp(c.tertiaryContainer, c.tertiary, 0.4)!,
      c.tertiaryContainer,
      Color.lerp(c.primary, c.tertiary, 0.5)!,
      c.error,
      c.primaryContainer,
      Color.lerp(c.tertiary, c.error, 0.3)!,
    ];
  }

  @override
  List<Color> get avatarColors {
    final c = scheme;
    return [
      c.primary,
      Color.lerp(c.primary, c.tertiary, 0.25)!,
      Color.lerp(c.primary, c.tertiary, 0.5)!,
      Color.lerp(c.primary, c.tertiary, 0.75)!,
      c.tertiary,
      c.error,
    ];
  }

  @override
  Color get pieceBlack => scheme.onSurface;

  @override
  Color get pieceWhite => scheme.surface;

  @override
  Color get protectWarmYellow =>
      Color.lerp(scheme.tertiary, scheme.tertiaryContainer, 0.5)!;

  @override
  Color get protectWarmOrange => scheme.tertiary;

  @override
  Color get protectNeutral => scheme.onSurface.withValues(alpha: 0.6);

  @override
  Color get protectCoolWhite => scheme.surfaceContainerHighest;

  @override
  List<Color> get protectPresets {
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

  @override
  List<String> get protectPresetNames => const [
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