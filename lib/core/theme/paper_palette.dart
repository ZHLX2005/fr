import 'package:flutter/material.dart';

/// 日式极简调色板：哑光奶白底、墨黑细字、克制动效
///
/// 所有颜色走这里，禁用 Material 默认蓝（0xFF1976D2 等）。
class PaperPalette {
  PaperPalette._();

  static const Color bg          = Color(0xFFF7F4EE); // 哑光奶白
  static const Color bgElevated  = Color(0xFFFFFCF5); // 卡片白
  static const Color ink         = Color(0xFF1F1B16); // 墨黑
  static const Color inkMuted    = Color(0xFF6F6A60); // 淡墨
  static const Color inkFaint    = Color(0xFFB8B2A4); // 雾墨
  static const Color line        = Color(0xFFE6DFD0); // 分隔线
  static const Color today       = Color(0xFFC8553D); // 朱砂红（当天）
  static const Color accent      = Color(0xFF8B6F47); // 茶色（主操作）
  static const Color highlight   = Color(0xFFE9B44C); // 黄土（生日高亮）
}