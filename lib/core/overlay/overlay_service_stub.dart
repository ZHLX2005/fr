// Web 平台的空实现
import 'package:flutter/foundation.dart';

Future<void> showOverlayWindow(VoidCallback onScreenshot) async {
  debugPrint('Overlay not supported on web');
}

Future<void> closeOverlayWindow() async {
  debugPrint('Overlay not supported on web');
}
