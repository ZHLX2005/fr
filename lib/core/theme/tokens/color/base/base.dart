// Layer 1 — 无主题色情况下的通用规范色（功能色 + 国际识别色）。
//
// 与 RawColors 的职责分离：
//   · RawColors = 跨主题共享的「中性骨架」白/黑/灰
//   · BaseColors = 跨主题锁定的「功能色」+「国际识别色」（不跟主题漂移）
//
// 消费规则：
//   · 当 AppThemeMode 为 null 或主题无覆盖时，strategy 的 default.dart 用本类
//   · 主题可在 themes/<theme>.dart 里 extends Default 重写部分角色覆盖本类

import 'package:flutter/material.dart';

class BaseColors {
  BaseColors._();

  // ─── 功能色（通用语义，跨主题锁定）────────────────────
  /// 成功/已就绪（绿）
  static const success = Color(0xFF4CAF50);
  /// 警告/注意（橙）
  static const warning = Color(0xFFFF9800);
  /// 信息/提示（蓝）
  static const info    = Color(0xFF2196F3);
  /// 危险/错误（红）
  static const danger  = Color(0xFFE53935);

  // ─── 国际识别色：俄罗斯方块 7 方块色 ────────────────────────
  // 跨主题锁定 —— I 永远是 cyan、O 永远是 amber，不随主题变色
  static const pieceI = Color(0xFF00BCD4);  // cyan 500    — I
  static const pieceO = Color(0xFFFFC107);  // amber 500   — O
  static const pieceT = Color(0xFF9C27B0);  // purple 500  — T
  static const pieceS = Color(0xFF4CAF50);  // green 500   — S
  static const pieceZ = Color(0xFFE53935);  // red 500     — Z
  static const pieceJ = Color(0xFF1976D2);  // blue 700    — J
  static const pieceL = Color(0xFFFF9800);  // orange 500  — L

  // ─── 国际识别色：团队卡 6 头像色 ─────────────────────────
  // 复用 piece 色板（缺 pieceZ 因 Z = 危险红在团队卡里复用意义不同）
  static const avatar1 = pieceI;
  static const avatar2 = pieceO;
  static const avatar3 = pieceT;
  static const avatar4 = pieceS;
  static const avatar5 = pieceJ;
  static const avatar6 = pieceL;
}