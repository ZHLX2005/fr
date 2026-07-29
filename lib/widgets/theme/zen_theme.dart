import 'package:flutter/material.dart';

class ZenColors {
  static const bg = Color(0xFFF4F1EA);
  static const ink = Color(0xFF2C2C2C);
  static const hair = Color(0xFFD9D5C8);
  static const secondary = Color(0xFF8A8475);
  static const sage = Color(0xFF7A9A7E);
  static const mutedRed = Color(0xFFA0594A);
  static const surface = Color(0xFFFBF8F1);
}

class ZenText {
  static const body = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    color: ZenColors.ink,
    height: 1.3,
  );
  static const label = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 13,
    color: ZenColors.secondary,
  );
  static const title = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: ZenColors.ink,
  );
  static const button = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  static const monoDigit = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 40,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.ink,
  );
  static const monoDigitLarge = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 64,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.ink,
  );
  static const monoDigitSmall = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 14,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.secondary,
  );
}

BoxDecoration zenCard({Color? color}) => BoxDecoration(
      color: color ?? ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1),
      borderRadius: BorderRadius.circular(6),
    );

BoxDecoration zenDottedZone() => BoxDecoration(
      color: ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1, style: BorderStyle.solid),
      borderRadius: BorderRadius.circular(6),
    );

ButtonStyle zenButton({Color? foreground, Color? border, Color? background}) =>
    OutlinedButton.styleFrom(
      foregroundColor: foreground ?? ZenColors.ink,
      side: BorderSide(color: border ?? ZenColors.hair),
      backgroundColor: background,
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: ZenText.button,
    );
