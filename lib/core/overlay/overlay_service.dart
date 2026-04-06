import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_overlay_window/src/models/overlay_position.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

/// 悬浮窗截屏服务
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;
  bool get isOverlayActive => _isOverlayActive;

  /// 检查悬浮窗权限
  Future<bool> checkOverlayPermission() async {
    if (Platform.isAndroid) {
      return await Permission.systemAlertWindow.isGranted;
    }
    return false;
  }

  /// 请求悬浮窗权限
  Future<bool> requestOverlayPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.systemAlertWindow.request();
      return status.isGranted;
    }
    return false;
  }

  /// 初始化悬浮窗
  Future<bool> initOverlay() async {
    if (Platform.isAndroid) {
      final hasPermission = await checkOverlayPermission();
      if (!hasPermission) {
        final granted = await requestOverlayPermission();
        if (!granted) {
          return false;
        }
      }

      // 配置悬浮窗
      await FlutterOverlayWindow.requestPermission();
      return true;
    }
    return false;
  }

  /// 显示悬浮截屏按钮
  Future<void> showOverlayButton({
    required VoidCallback onScreenshot,
  }) async {
    if (!Platform.isAndroid) return;

    _isOverlayActive = true;

    // 创建悬浮按钮overlay
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

  /// 隐藏悬浮按钮
  Future<void> hideOverlayButton() async {
    if (!Platform.isAndroid) return;

    _isOverlayActive = false;
    await FlutterOverlayWindow.closeOverlay();
  }

  /// 切换悬浮按钮显示状态
  Future<void> toggleOverlay({
    required VoidCallback onScreenshot,
  }) async {
    if (_isOverlayActive) {
      await hideOverlayButton();
    } else {
      await showOverlayButton(onScreenshot: onScreenshot);
    }
  }

  /// 获取截图保存目录
  Future<Directory> getScreenshotDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final screenshotDir = Directory('${directory.path}/screenshots');
    if (!await screenshotDir.exists()) {
      await screenshotDir.create(recursive: true);
    }
    return screenshotDir;
  }
}

/// 悬浮窗权限状态
enum OverlayPermissionStatus {
  unknown,
  granted,
  denied,
  permanentlyDenied,
}
