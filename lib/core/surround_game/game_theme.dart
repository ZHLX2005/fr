/// 围追堵截主题配色方案
///
/// 提供两套主题配色：
/// - [GameTheme.defaultTheme]：米白/棕古典风格（默认），暖色调棋盘配色
/// - [GameTheme.lightTheme]：紫色系轻快风格
///
/// 每套包含背景色、格子色、墙壁色、面板色、按钮色、玩家色等
/// 完整颜色体系，通过 [toggle] 可切换主题。
import 'package:flutter/material.dart';

/// Quoridor 配色方案
///
/// 默认：米白背景 + 米白棕色格子（用户要求）
/// isLight=true：紫色亮色主题（对应 Swift 亮色）
class GameTheme {
  final bool isLight;

  const GameTheme({this.isLight = false});

  // ── 默认（米白/棕） ──
  static const _darkBg = Color(0xFFF8F0E3);       // 米白
  static const _darkCell = Color(0xFFEDE3D0);      // 浅米
  static const _darkCellBorder = Color(0xFFC4B49A); // 米棕
  static const _darkWall = Color(0xFF7CFFE5);
  static const _darkPanel = Color(0xFFE8DDCB);     // 面板底色
  static const _darkPanelBorder = Color(0xFFD4C5A9);
  static const _darkBtnBg = Color(0xFFF5EDE0);
  static const _darkBtnBorder = Color(0xFFD4C5A9);

  // ── 亮色（Swift 原版紫色亮色） ──
  static const _lightBg = Color(0xFFBA99F1);
  static const _lightCell = Color(0xFFFFFFFF);
  static const _lightCellBorder = Color(0xFF89DFF1);
  static const _lightWall = Color(0xFF76FFD0);
  static const _lightPanel = Color(0xFFC9ADE8);
  static const _lightPanelBorder = Color(0xFFB89DE0);
  static const _lightBtnBg = Color(0xFFD4BCF0);
  static const _lightBtnBorder = Color(0xFFB89DE0);

  // ── 棋子 + 玩家墙壁 ──
  static const topPlayer = Color(0xFFF4A523);
  static const bottomPlayer = Color(0xFFEE8E9A);
  static const topWall = Color(0xFFF4A523);    // 橙色（Top）
  static const bottomWall = Color(0xFFEE8E9A);  // 粉色（Bottom）

  Color get background => isLight ? _lightBg : _darkBg;
  Color get cellFill => isLight ? _lightCell : _darkCell;
  Color get cellBorder => isLight ? _lightCellBorder : _darkCellBorder;
  Color get wall => isLight ? _lightWall : _darkWall;
  Color get panelBg => isLight ? _lightPanel : _darkPanel;
  Color get panelBorder => isLight ? _lightPanelBorder : _darkPanelBorder;
  Color get btnBg => isLight ? _lightBtnBg : _darkBtnBg;
  Color get btnBorder => isLight ? _lightBtnBorder : _darkBtnBorder;
  Color get btnText => isLight ? Colors.black87 : const Color(0xFF5C4E3A);
  Color get btnSub => isLight ? Colors.black54 : const Color(0xFF9C8E7A);

  /// 切换主题
  GameTheme get toggle => GameTheme(isLight: !isLight);
}
