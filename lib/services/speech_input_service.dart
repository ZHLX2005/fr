import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';

/// 语音输入服务
/// 支持Web、Android、iOS平台
class SpeechInputService {
  static final SpeechToText _speechToText = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  /// 初始化语音识别
  Future<bool> initialize() async {
    try {
      _isAvailable = await _speechToText.initialize();
      debugPrint('语音识别初始化: $_isAvailable');
      return _isAvailable;
    } catch (e) {
      debugPrint('语音识别初始化失败: $e');
      return false;
    }
  }

  /// 检查麦克风权限
  Future<bool> checkPermission() async {
    if (kIsWeb) {
      // Web环境：浏览器会自动请求权限
      return true;
    }

    // 移动端：检查录音权限
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 开始语音输入
  /// onResult: 识别文字的回调
  /// onListeningStateChanged: 监听状态变化的回调
  Future<bool> startListening({
    required Function(String text) onResult,
    Function(String state)? onListeningStateChanged,
  }) async {
    if (_isListening) {
      debugPrint('语音识别已在运行中');
      return false;
    }

    if (!_isAvailable) {
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('语音识别不可用');
        return false;
      }
    }

    // 检查权限
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      debugPrint('没有麦克风权限');
      return false;
    }

    try {
      _isListening = true;
      onListeningStateChanged?.call('listening');

      await _speechToText.listen(
        onResult: (result) {
          final recognizedWords = result.recognizedWords;
          debugPrint('识别结果: $recognizedWords');
          onResult(recognizedWords);

          if (result.finalResult) {
            _isListening = false;
            onListeningStateChanged?.call('stopped');
          }
        },
        listenFor: Duration(seconds: 30), // 最长监听30秒
        pauseFor: Duration(seconds: 3),   // 暂停3秒后自动停止
        partialResults: true,              // 启用部分结果
        localeId: 'zh_CN',                // 中文
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        onSoundLevelChange: (level) {
          debugPrint('音量: $level');
        },
      );

      return true;
    } catch (e) {
      debugPrint('启动语音识别失败: $e');
      _isListening = false;
      onListeningStateChanged?.call('error');
      return false;
    }
  }

  /// 停止语音输入
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _speechToText.stop();
      _isListening = false;
      debugPrint('语音识别已停止');
    } catch (e) {
      debugPrint('停止语音识别失败: $e');
    }
  }

  /// 取消语音输入
  Future<void> cancelListening() async {
    if (!_isListening) return;

    try {
      await _speechToText.cancel();
      _isListening = false;
      debugPrint('语音识别已取消');
    } catch (e) {
      debugPrint('取消语音识别失败: $e');
    }
  }

  /// 获取可用的语言列表
  Future<List<String>> getAvailableLanguages() async {
    try {
      final languages = await _speechToText.locales();
      return languages.map((locale) => locale.localeId).toList();
    } catch (e) {
      debugPrint('获取语言列表失败: $e');
      return ['zh_CN', 'en_US'];
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    try {
      await _speechToText.cancel();
      _isListening = false;
    } catch (e) {
      debugPrint('释放语音识别资源失败: $e');
    }
  }
}
