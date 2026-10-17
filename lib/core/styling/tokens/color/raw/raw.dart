// Layer 1 — 跨主题共享的原料色板。
//
// 用途：onPrimary 黑白、surface 容器色、shadow alpha-black 等
// 在多套主题下复用的"中性骨架色"。主题专属色不放这里。

import 'package:flutter/material.dart';

class RawColors {
  RawColors._();

  // -- 纯白与近黑 ----------------------------------------------
  /// 浅色主题 onPrimary 用色（light/pink/green/orange/rose 共用）
  static const pureWhite = Color(0xFFFFFFFF);

  /// 深色主题 onPrimary 用色（dark 用）
  static const nearBlack = Color(0xFF0F1419);

  /// 暮紫主题 onPrimary 用色（purple 用，深紫黑）
  static const deepBlack = Color(0xFF1B1722);

  // -- 中性灰阶 -------------------------------------------------
  // 9 档中性灰，从深到浅，与 M3 Neutral Variant 对齐
  static const neutral10 = Color(0xFF1A1C1E);
  static const neutral20 = Color(0xFF2F3133);
  static const neutral30 = Color(0xFF45484A);
  static const neutral40 = Color(0xFF5C5F62);
  static const neutral50 = Color(0xFF75787B);
  static const neutral60 = Color(0xFF8E9194);
  static const neutral70 = Color(0xFFA9ACAE);
  static const neutral80 = Color(0xFFC4C7C9);
  static const neutral90 = Color(0xFFE0E2E4);
  static const neutral95 = Color(0xFFEFEFF1);
  static const neutral99 = Color(0xFFFBFBFC);

  // -- 阴影色（alpha 黑） ----------------------------------------
  /// 浅色主题 cardShadow 用的 8% 黑
  static const shadowLight = Color(0x14000000);

  /// 深色主题 cardShadow 用的 30% 黑
  static const shadowMedium = Color(0x4D000000);

  /// 暮紫主题 cardShadow 用的 40% 黑
  static const shadowHeavy = Color(0x66000000);
}