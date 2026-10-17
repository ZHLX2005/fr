import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 日式极简字体封装（v7：颜色跟主题，调用方传或走全局 TextTheme）：
/// - 标题/衬线大字：Cormorant Garamond
/// - 正文/小字：Inter
class AppText {
  AppText._();

  static TextStyle display({Color? color}) => GoogleFonts.cormorantGaramond(
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.2,
      );

  static TextStyle title({Color? color}) => GoogleFonts.cormorantGaramond(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.25,
      );

  static TextStyle body({Color? color}) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  static TextStyle caption({Color? color}) => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.3,
      );
}