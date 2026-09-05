import 'package:flutter/services.dart';

/// 「线」允许横竖屏；离开模块时由调用方恢复。
class LineOrientation {
  static Future<void> enableAll() {
    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> portraitOnly() {
    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
}
