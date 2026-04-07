// Web 平台的空实现
import 'package:flutter/foundation.dart';

// 内部接口 - Web 上返回默认值
Future<bool> _checkOverlayPermission() async => false;

Future<bool> _requestOverlayPermission() async => false;

Future<void> _showOverlay(VoidCallback onScreenshot) async {
  debugPrint('Overlay not supported on web');
}

Future<void> _closeOverlay() async {
  debugPrint('Overlay not supported on web');
}
