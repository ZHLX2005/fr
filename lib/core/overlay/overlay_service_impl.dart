// Android 平台的 flutter_overlay_window 实现
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_overlay_window/src/models/overlay_position.dart';

// 内部接口 - 由 overlay_service.dart 调用
Future<bool> _checkOverlayPermission() async {
  if (!Platform.isAndroid) return false;
  return await FlutterOverlayWindow.checkPermission();
}

Future<bool> _requestOverlayPermission() async {
  if (!Platform.isAndroid) return false;
  return await FlutterOverlayWindow.requestPermission();
}

Future<void> _showOverlay(VoidCallback onScreenshot) async {
  if (!Platform.isAndroid) return;

  // 先检查权限
  bool hasPermission = await FlutterOverlayWindow.checkPermission();

  // 如果没有权限，先请求
  if (!hasPermission) {
    hasPermission = await FlutterOverlayWindow.requestPermission();
  }

  // 如果还是没有权限，抛出错误让调用者处理
  if (!hasPermission) {
    throw Exception('悬浮窗权限被拒绝');
  }

  // 显示悬浮窗
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

Future<void> _closeOverlay() async {
  if (!Platform.isAndroid) return;
  await FlutterOverlayWindow.closeOverlay();
}
