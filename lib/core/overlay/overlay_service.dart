import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';

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
    // 使用 flutter_overlay_window 本身检查权限
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  /// 请求悬浮窗权限
  Future<bool> requestOverlayPermission() async {
    if (!isSupported) return false;
    // 请求权限 - flutter_overlay_window.requestPermission 会打开系统设置页面
    final result = await FlutterOverlayWindow.requestPermission();
    _overlayPermissionGranted = result ?? false;
    return result ?? false;
  }

  /// 初始化悬浮窗
  Future<bool> initOverlay() async {
    if (!isSupported) return false;
    return await requestOverlayPermission();
  }

  /// 显示悬浮截屏按钮
  Future<void> showOverlayButton({
    required VoidCallback onScreenshot,
  }) async {
    if (!isSupported) return;

    // 请求权限并显示悬浮窗
    final granted = await FlutterOverlayWindow.requestPermission();
    if (granted != true) {
      throw Exception('悬浮窗权限被拒绝');
    }

    _isOverlayActive = true;
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      flag: OverlayFlag.defaultFlag,
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
    if (!isSupported) return;

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

  bool _overlayPermissionGranted = false;
}

/// 悬浮窗权限状态
enum OverlayPermissionStatus {
  unknown,
  granted,
  denied,
  permanentlyDenied,
}
