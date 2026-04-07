// Android 平台的 flutter_overlay_window 实现
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_overlay_window/src/models/overlay_position.dart';

Future<void> showOverlayWindow(VoidCallback onScreenshot) async {
  await FlutterOverlayWindow.requestPermission();
  await FlutterOverlayWindow.showOverlay(
    enableDrag: true,
    flag: OverlayFlag.clickThrough,
    visibility: NotificationVisibility.visibilityPublic,
    positionGravity: PositionGravity.right,
    height: 60,
    width: 60,
    alignment: OverlayAlignment.topRight,
    startPosition: const OverlayPosition(0, 100),
  );
}

Future<void> closeOverlayWindow() async {
  await FlutterOverlayWindow.closeOverlay();
}
