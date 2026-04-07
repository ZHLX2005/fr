import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// 条件导入 flutter_overlay_window（仅 Android）
import 'overlay_service_impl.dart'
    if (dart.library.html) 'overlay_service_stub.dart';

/// 悬浮窗服务（跨平台兼容）
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;

  bool get isOverlayActive => _isOverlayActive;

  /// 是否支持悬浮窗（仅 Android）
  bool get isSupported => Platform.isAndroid;

  /// 检查悬浮窗权限
  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    return await _checkOverlayPermission();
  }

  /// 请求悬浮窗权限
  Future<bool> requestOverlayPermission() async {
    if (!isSupported) return false;
    return await _requestOverlayPermission();
  }

  /// 初始化悬浮窗
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
  Future<void> showOverlayButton({
    required VoidCallback onScreenshot,
  }) async {
    if (!isSupported) return;

    _isOverlayActive = true;
    await _showOverlay(onScreenshot);
  }

  /// 隐藏悬浮按钮
  Future<void> hideOverlayButton() async {
    if (!isSupported) return;

    _isOverlayActive = false;
    await _closeOverlay();
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
