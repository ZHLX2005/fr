// Color 工具类

import 'package:flutter/material.dart';

class ColorUtils {
  static Color fromHex(String hex) {
    final cleaned = hex.replaceAll('#', '').toUpperCase();
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    if (cleaned.length == 8) {
      return Color(int.parse(cleaned, radix: 16));
    }
    throw ArgumentError('Invalid hex: $hex');
  }

  static Color bestOnColor(Color bg) {
    final l = bg.computeLuminance();
    return l > 0.55 ? Colors.black : Colors.white;
  }

  static Color highlight(Color c, {double t = 0.10}) {
    int mix(int a, int b, double t) =>
        (a + (b - a) * t).round().clamp(0, 255);
    return Color.fromARGB(
      (c.a * 255).round(),
      mix((c.r * 255).round(), 255, t),
      mix((c.g * 255).round(), 255, t),
      mix((c.b * 255).round(), 255, t),
    );
  }
}
