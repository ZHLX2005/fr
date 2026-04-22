import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 悬浮窗服务（原生 Android 实现）
/// 负责与 native/overlay/FloatingWindowManager 桥接
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;
  bool _hasOverlayPermission = false;

  static const _channel = MethodChannel(
    'com.example.flutter_application_1/floating',
  );

  bool get isOverlayActive => _isOverlayActive;
  bool get hasOverlayPermission => _hasOverlayPermission;
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  /// 初始化服务
  Future<void> init() async {
    if (!isSupported) return;
    await checkOverlayPermission();
    _setupMethodCallHandler();
  }

  /// 设置方法通道监听（仅保留截图权限回调）
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onScreenshotPermissionGranted':
          _onScreenshotPermissionGranted?.call();
          break;
        case 'onScreenshotPermissionDenied':
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

  /// 保存 AI 配置到原生层（API Key 等由 Kotlin 存储和使用）
  Future<void> saveAiConfig({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    bool directScreenshot = false,
  }) async {
    try {
      await _channel.invokeMethod('saveAiConfig', {
        'apiUrl': apiUrl,
        'apiKey': apiKey,
        'model': model,
        'systemPrompt': systemPrompt,
        'directScreenshot': directScreenshot,
      });
    } on PlatformException catch (e) {
      debugPrint('保存配置失败: ${e.message}');
    }
  }

  /// 加载 AI 配置（用于回填表单）
  Future<Map<String, dynamic>> loadAiConfig() async {
    const defaultApiUrl =
        'https://open.bigmodel.cn/api/paas/v4/chat/completions';
    const defaultModel = 'glm-4v-flash';
    const defaultSystemPrompt = '你是一个专业的AI助手，请根据图片回答用户问题。';

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'loadAiConfig',
      );
      if (result != null) {
        final apiUrl = result['apiUrl'] as String?;
        final apiKey = result['apiKey'] as String?;
        final model = result['model'] as String?;
        final systemPrompt = result['systemPrompt'] as String?;
        final directScreenshot = result['directScreenshot'] as bool? ?? false;

        return {
          'apiUrl': (apiUrl != null && apiUrl.isNotEmpty)
              ? apiUrl
              : defaultApiUrl,
          'apiKey': apiKey ?? '',
          'model': (model != null && model.isNotEmpty) ? model : defaultModel,
          'systemPrompt': systemPrompt ?? defaultSystemPrompt,
          'directScreenshot': directScreenshot,
        };
      }
    } on PlatformException catch (e) {
      debugPrint('加载配置失败: ${e.message}');
    }
    return {
      'apiUrl': defaultApiUrl,
      'apiKey': '',
      'model': defaultModel,
      'systemPrompt': defaultSystemPrompt,
      'directScreenshot': false,
    };
  }

  /// 检查悬浮窗权限（Android 6.0+ 需要用户在系统设置中开启）
  Future<bool> checkOverlayPermission() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'checkOverlayPermission',
      );
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

  /// 初始化悬浮窗（同时检查权限）
  Future<bool> initOverlay() async {
    if (!isSupported) return false;

    final hasPermission = await checkOverlayPermission();
    if (!hasPermission) {
      await requestOverlayPermission();
      return false;
    }

    return true;
  }

  /// 显示悬浮截屏按钮
  /// 返回 true 表示成功，false 表示需要先授权
  Future<bool> showOverlayButton() async {
    if (!isSupported) return false;

    final hasPermission = await checkOverlayPermission();
    if (!hasPermission) {
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
}

/// 悬浮窗权限状态
enum OverlayPermissionStatus { unknown, granted, denied, permanentlyDenied }
