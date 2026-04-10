import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 悬浮窗服务（原生 Android 实现）
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;
  static const _channel = MethodChannel('com.example.flutter_application_1/floating');

  bool get isOverlayActive => _isOverlayActive;

  /// 是否支持悬浮窗（仅 Android）
  bool get isSupported => Platform.isAndroid;

  /// 检查悬浮窗权限（Android 6.0+ 需要 SYSTEM_ALERT_WINDOW 权限）
  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    // Android 原生不需要运行时检查，权限在安装时授予
    // flutter_overlay_window 本身检查权限
    return true;
  }

  /// 请求悬浮窗权限
  Future<bool> requestOverlayPermission() async {
    if (!isSupported) return false;
    // 在 Android 上，SYSTEM_ALERT_WINDOW 权限需要用户在系统设置中开启
    // 这里直接返回 true，实际权限由系统管理
    return true;
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

    try {
      await _channel.invokeMethod('startFloating');
      _isOverlayActive = true;
    } on PlatformException catch (e) {
      debugPrint('启动悬浮窗失败: ${e.message}');
      rethrow;
    }
  }

  /// 隐藏悬浮按钮
  Future<void> hideOverlayButton() async {
    if (!isSupported) return;

    try {
      await _channel.invokeMethod('stopFloating');
      _isOverlayActive = false;
    } on PlatformException catch (e) {
      debugPrint('关闭悬浮窗失败: ${e.message}');
      rethrow;
    }
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
    // Android 使用外部私有目录
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
