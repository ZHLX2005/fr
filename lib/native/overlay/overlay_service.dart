import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  /// 获取当前 AI 配置（用于回填表单）
  Map<String, String> get aiConfig => {
    'apiUrl': _aiApiUrl,
    'apiKey': _aiApiKey,
    'model': _aiModel,
    'systemPrompt': _aiSystemPrompt,
  };

  /// 初始化服务
  Future<void> init() async {
    if (!isSupported) return;
    await checkOverlayPermission();
    await checkScreenshotPermission();
    _setupMethodCallHandler();
    // 加载已保存的配置
    await loadAiConfig();
  }

  /// 从原生层加载 AI 配置
  Future<void> loadAiConfig() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('loadAiConfig');
      if (result != null) {
        final loadedUrl = result['apiUrl'] as String?;
        if (loadedUrl != null && loadedUrl.isNotEmpty) _aiApiUrl = loadedUrl;
        final loadedKey = result['apiKey'] as String?;
        if (loadedKey != null && loadedKey.isNotEmpty) _aiApiKey = loadedKey;
        final loadedModel = result['model'] as String?;
        if (loadedModel != null && loadedModel.isNotEmpty) _aiModel = loadedModel;
        final loadedPrompt = result['systemPrompt'] as String?;
        if (loadedPrompt != null && loadedPrompt.isNotEmpty) _aiSystemPrompt = loadedPrompt;
      }
    } on PlatformException catch (e) {
      debugPrint('加载配置失败: ${e.message}');
    }
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
        case 'onRegionCaptured':
          final data = call.arguments as Uint8List?;
          _pendingScreenshot = data;
          _onRegionCaptured?.call(data);
          break;
        case 'onAiQuestion':
          // 原生层触发的 AI 问答
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null) {
            final question = args['question'] as String? ?? '';
            final imagePath = args['imagePath'] as String?;
            if (imagePath != null && question.isNotEmpty) {
              await _handleAiQuestion(question, imagePath);
            }
          }
          break;
      }
    });
  }

  /// 处理 AI 问题（由原生层调用）
  Future<void> _handleAiQuestion(String question, String imagePath) async {
    try {
      // 读取文件内容
      final file = File(imagePath);
      final imageBytes = await file.readAsBytes();
      // 删除临时文件
      await file.delete();

      await callAiApi(
        question: question,
        imageBytes: imageBytes,
        onChunk: (chunk) {
          sendAiAnswerChunk(chunk);
        },
        onError: (error) {
          sendAiAnswerError(error ?? '未知错误');
        },
        onDone: () {
          sendAiAnswerDone();
        },
      );
    } catch (e) {
      sendAiAnswerError('读取图片失败: $e');
    }
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

  /// 保存 AI 配置到原生层
  Future<void> saveAiConfig({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
  }) async {
    try {
      // 同时更新本地变量，确保 callAiApi 使用最新配置
      _aiApiUrl = apiUrl;
      _aiApiKey = apiKey;
      _aiModel = model;
      _aiSystemPrompt = systemPrompt;

      await _channel.invokeMethod('saveAiConfig', {
        'apiUrl': apiUrl,
        'apiKey': apiKey,
        'model': model,
        'systemPrompt': systemPrompt,
      });
    } on PlatformException catch (e) {
      debugPrint('保存配置失败: ${e.message}');
    }
  }

  /// 区域截图数据回调
  void Function(Uint8List? data)? _onRegionCaptured;
  void setOnRegionCaptured(void Function(Uint8List? data)? callback) {
    _onRegionCaptured = callback;
  }

  /// 待处理的截图数据
  Uint8List? _pendingScreenshot;
  Uint8List? get pendingScreenshot => _pendingScreenshot;

  /// 清空待处理截图
  void clearPendingScreenshot() {
    _pendingScreenshot = null;
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

  /// 保存截图到图库
  Future<bool> saveScreenshotToGallery(Uint8List imageData) async {
    if (!isSupported) return false;

    try {
      final result = await _channel.invokeMethod('saveScreenshotToGallery', imageData);
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('保存截图失败: ${e.message}');
      return false;
    }
  }

  /// AI 配置（从 Flutter 配置）
  String _aiApiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  String _aiApiKey = '';
  String _aiModel = 'glm-4v-flash';
  String _aiSystemPrompt = '你是一个专业的AI助手，请根据图片回答用户问题。';

  /// 调用 AI API（由原生层触发，Flutter 发送流式答案回原生）
  Future<void> callAiApi({
    required String question,
    required Uint8List imageBytes,
    required Function(String) onChunk,
    required Function(String?) onError,
    required Function() onDone,
  }) async {
    if (!isSupported) {
      onError('仅支持 Android 设备');
      return;
    }

    if (_aiApiKey.isEmpty) {
      onError('请先配置 API Key');
      return;
    }

    try {
      // 将图片转为 base64
      final imageBase64 = base64Encode(imageBytes);

      // 构建请求
      final uri = Uri.parse(_aiApiUrl);
      final httpClient = HttpClient();
      final request = await httpClient.openUrl('POST', uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $_aiApiKey');

      final body = {
        'model': _aiModel,
        'messages': [
          {'role': 'system', 'content': _aiSystemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$imageBase64'}},
              {'type': 'text', 'text': question}
            ]
          }
        ],
        'stream': true,
      };

      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();

      if (response.statusCode != 200) {
        onError('API 错误: ${response.statusCode}');
        return;
      }

      // 处理 SSE 流
      await for (final chunk in response.transform(const SystemEncoding().decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') break;

            // 解析 SSE data
            final content = _parseSseData(data);
            if (content.isNotEmpty) {
              onChunk(content);
            }
          }
        }
      }

      onDone();
    } catch (e) {
      onError('请求失败: $e');
    }
  }

  /// 解析 SSE data
  String _parseSseData(String json) {
    try {
      // 简单解析 JSON
      final match = RegExp(r'"content"\s*:\s*"([^"]*)"').firstMatch(json);
      return match?.group(1) ?? '';
    } catch (e) {
      return '';
    }
  }

  /// 发送 AI 答案片段给原生显示
  void sendAiAnswerChunk(String chunk) {
    _channel.invokeMethod('onAiAnswerChunk', {'chunk': chunk});
  }

  /// 发送 AI 错误给原生显示
  void sendAiAnswerError(String error) {
    _channel.invokeMethod('onAiAnswerError', {'error': error});
  }

  /// 发送 AI 完成信号给原生
  void sendAiAnswerDone() {
    _channel.invokeMethod('onAiAnswerDone', {});
  }

  /// 发送 AI 开始给原生（用于显示 loading）
  void sendAiAnswerStart() {
    _channel.invokeMethod('onAiAnswerStart', {});
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