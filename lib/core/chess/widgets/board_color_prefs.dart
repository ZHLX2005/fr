// lib/core/chess/widgets/board_color_prefs.dart
//
// 自定义棋盘配色偏好 —— SharedPreferences 持久化用户自定义的棋盘颜色。
//
// 设计（遵循 lib/core/chess/skins/chess_skin_prefs.dart 的静态 key 模式）：
//   · 静态 key const（与 ChessSkinPrefs._key 同级）
//   · read()/write()/clear() 各自 getInstance，轻量无状态
//   · 只 round-trip lightSquare / darkSquare（v1 主线：用户最常改的两主格色），
//     其余 BoardPalette 角色不持久化（内存态可用，未来扩展再补 key）
//   · 无记录 / 自定义未启用 → read() 返回 null（跟随主题）
//
// 存储格式：Color → int（ARGB 32 位值）经 toARGB32() 持久化，
// 读回用 Color(argbInt) 还原。

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'board_palette.dart';

/// 自定义棋盘配色偏好 —— SharedPreferences 持久化。
class BoardColorPrefs {
  BoardColorPrefs._();

  /// 自定义是否启用（false = 跟随主题，忽略下面的颜色值）。
  static const String _kCustom = 'chess_board_custom';

  /// 浅色格 ARGB int。
  static const String _kLight = 'chess_board_light';

  /// 深色格 ARGB int。
  static const String _kDark = 'chess_board_dark';

  /// 读取当前自定义棋盘配色。
  ///
  /// 返回 null 表示"跟随主题"（未启用自定义，或没有已保存的值）。
  static Future<BoardPalette?> read() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kCustom) != true) return null;
    final light = prefs.getInt(_kLight);
    final dark = prefs.getInt(_kDark);
    if (light == null && dark == null) return null;
    return BoardPalette(
      lightSquare: light == null ? null : Color(light),
      darkSquare: dark == null ? null : Color(dark),
    );
  }

  /// 写入自定义棋盘配色（启用自定义并持久化两主格色）。
  ///
  /// 注意：只持久化 lightSquare / darkSquare —— BoardPalette 的其余角色
  /// 为扩展预留，v1 不做持久化。
  static Future<void> write(BoardPalette palette) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCustom, true);
    if (palette.lightSquare != null) {
      await prefs.setInt(_kLight, palette.lightSquare!.toARGB32());
    }
    if (palette.darkSquare != null) {
      await prefs.setInt(_kDark, palette.darkSquare!.toARGB32());
    }
  }

  /// 清除自定义 → 跟随主题。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCustom, false);
    await prefs.remove(_kLight);
    await prefs.remove(_kDark);
  }
}
