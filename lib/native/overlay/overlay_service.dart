import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 悬浮窗服务（原生 Android 实现）
/// 负责与 native/overlay/FloatingWindowManager 桥接
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;
  bool _hasOverlayPermission = false;
  bool _hasScreenshotPermission = false;

  static const _channel = MethodChannel('com.example.flutter_application_1/floating');

  bool get isOverlayActive => _isOverlayActive;
  bool get hasOverlayPermission => _hasOverlayPermission;
  bool get hasScreenshotPermission => _hasScreenshotPermission;
  bool get isSupported => Platform.isAndroid;

  /// 初始化服务
  Future<void> init() async {
    if (!isSupported) return;
    await checkOverlayPermission();
    await checkScreenshotPermission();
    _setupMethodCallHandler();
  }

  /// 设置方法通道监听
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onScreenshotPermissionGranted':
          _hasScreenshotPermission = true;
          _onScreenshotPermissionGranted?.call();
          break;
        case 'onScreenshotPermissionDenied':
          _hasScreenshotPermission = false;
          _onScreenshotPermissionDenied?.call();
          break;
        case 'onScreenshotCompleted':
          _onScreenshotCompleted?.call(call.arguments as String?);
          break;
      }
    });
  }

  /// 截图权限授予回调
  VoidCallback? _onScreenshotPermissionGranted;
  void setOnScreenshotPermissionGranted(VoidCallback? callback) {
    _onScreenshotPermissionGranted = callback;
  }

  /// 截图权限拒绝回调
  VoidCallback? _onScreenshotPermissionDenied;
  void setOnScreenshotPermissionDenied(VoidCallback? callback) {
    _onScreenshotPermissionDenied = callback;
  }

  /// 截图完成回调
  void Function(String? path)? _onScreenshotCompleted;
  void setOnScreenshotCompleted(void Function(String? path)? callback) {
    _onScreenshotCompleted = callback;
  }

  /// 检查悬浮窗权限（Android 6.0+ 需要用户在系统设置中开启）
  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('checkOverlayPermission');
      _hasOverlayPermission = result ?? false;
      return _hasOverlayPermission;
    } on PlatformException catch (e) {
      debugPrint('检查悬浮窗权限失败: ${e.message}');
      _hasOverlayPermission = false;
      return false;
    }
  }

  /// 请求悬浮窗权限 - 跳转到系统设置页面
  Future<void> requestOverlayPermission() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      debugPrint('请求悬浮窗权限失败: ${e.message}');
    }
  }

  /// 检查截图权限
  Future<bool> checkScreenshotPermission() async {
    if (!isSupported) return false;
    // Android 截图权限通过 MediaProjection 获取，这里检查服务是否已启动
    _hasScreenshotPermission = await isFloatingShowing();
    return _hasScreenshotPermission;
  }

  /// 请求截图权限（会弹出系统授权对话框）
  Future<void> requestScreenshotPermission() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('requestScreenshotPermission');
    } on PlatformException catch (e) {
      debugPrint('请求截图权限失败: ${e.message}');
    }
  }

  /// 检查悬浮窗是否正在显示
  Future<bool> isFloatingShowing() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isFloatingShowing');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 初始化悬浮窗（同时检查权限）
  Future<bool> initOverlay() async {
    if (!isSupported) return false;

    // 先检查权限
    final hasPermission = await checkOverlayPermission();
    if (!hasPermission) {
      // 没有悬浮窗权限，先请求
      await requestOverlayPermission();
      return false;
    }

    return true;
  }

  /// 显示悬浮截屏按钮
  /// 返回 true 表示成功，false 表示需要先授权
  Future<bool> showOverlayButton({
    VoidCallback? onScreenshot,
  }) async {
    if (!isSupported) return false;

    // 再次检查权限
    final hasPermission = await checkOverlayPermission();
    if (!hasPermission) {
      // 没有权限，跳转到设置页面
      await requestOverlayPermission();
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('startFloating');
      _isOverlayActive = result ?? false;
      return _isOverlayActive;
    } on PlatformException catch (e) {
      debugPrint('启动悬浮窗失败: ${e.message}');
      _isOverlayActive = false;
      return false;
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
    }
  }

  /// 切换悬浮按钮显示状态
  Future<void> toggleOverlay({
    VoidCallback? onScreenshot,
  }) async {
    if (_isOverlayActive) {
      await hideOverlayButton();
    } else {
      await showOverlayButton(onScreenshot: onScreenshot);
    }
  }

  /// 执行屏幕截图（需要先调用 showOverlayButton 显示悬浮窗）
  Future<void> captureScreen() async {
    if (!isSupported) return;

    try {
      await _channel.invokeMethod('captureScreen');
    } on PlatformException catch (e) {
      debugPrint('截屏失败: ${e.message}');
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