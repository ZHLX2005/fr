import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'overlay_service_android.dart'
    if (dart.library.html) 'overlay_service_stub.dart';

/// 悬浮窗服务接口
abstract class OverlayServiceInterface {
  bool get isSupported;
  bool get isOverlayActive;
  Future<bool> checkOverlayPermission();
  Future<bool> requestOverlayPermission();
  Future<bool> initOverlay();
  Future<void> showOverlayButton({required VoidCallback onScreenshot});
  Future<void> hideOverlayButton();
  Future<void> toggleOverlay({required VoidCallback onScreenshot});
  Future<Directory> getScreenshotDirectory();
}

/// 悬浮窗服务（跨平台兼容）
class OverlayService implements OverlayServiceInterface {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;

  @override
  bool get isOverlayActive => _isOverlayActive;

  /// 是否支持悬浮窗（仅 Android）
  @override
  bool get isSupported => Platform.isAndroid;

  /// 检查悬浮窗权限
  @override
  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    return await Permission.systemAlertWindow.isGranted;
  }

  /// 请求悬浮窗权限
  @override
  Future<bool> requestOverlayPermission() async {
    if (!isSupported) return false;
    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }

  /// 初始化悬浮窗
  @override
  Future<bool> initOverlay() async {
    if (!isSupported) return false;

    final hasPermission = await checkOverlayPermission();
    if (!hasPermission) {
      final granted = await requestOverlayPermission();
      if (!granted) return false;
    }
    return true;
  }

  /// 显示悬浮截屏按钮
  @override
  Future<void> showOverlayButton({
    required VoidCallback onScreenshot,
  }) async {
    if (!isSupported) return;

    _isOverlayActive = true;
    await showOverlayWindow(onScreenshot);
  }

  /// 隐藏悬浮按钮
  @override
  Future<void> hideOverlayButton() async {
    if (!isSupported) return;

    _isOverlayActive = false;
    await closeOverlayWindow();
  }

  /// 切换悬浮按钮显示状态
  @override
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
  @override
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
