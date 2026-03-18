import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// 录音服务
/// 支持 Android、iOS 和 Web 平台
class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;
  DateTime? _startTime;

  bool get isRecording => _isRecording;
  String? get recordPath => _recordPath;

  /// 检查麦克风权限
  Future<bool> checkPermission() async {
    if (kIsWeb) {
      // Web 平台使用浏览器 API，需要用户手动授权
      return await _recorder.hasPermission();
    }
    // 移动端检查权限
    return await _recorder.hasPermission();
  }

  /// 开始录音
  Future<bool> startRecording() async {
    if (_isRecording) return false;

    try {
      // 检查权限
      if (!await checkPermission()) {
        debugPrint('麦克风权限被拒绝');
        return false;
      }

      // 获取保存路径
      String path;
      if (kIsWeb) {
        // Web 平台：录音会保存在内存中
        path = 'recording.webm';
      } else {
        // 移动端：保存到临时目录
        final dir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        path = '${dir.path}/recording_$timestamp.m4a';
      }

      // 配置录音参数
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      // 开始录音
      await _recorder.start(config, path: path);
      _isRecording = true;
      _recordPath = path;
      _startTime = DateTime.now();

      debugPrint('开始录音: $path');
      return true;
    } catch (e) {
      debugPrint('开始录音失败: $e');
      return false;
    }
  }

  /// 停止录音并返回录音时长
  Future<(String?, int)> stopRecordingWithDuration() async {
    if (!_isRecording) return (null, 0);

    try {
      // 先获取时长（在清除 _startTime 之前）
      final durationSeconds = getDurationInSeconds();

      final path = await _recorder.stop();
      _isRecording = false;
      _startTime = null;

      debugPrint('停止录音: $path, 时长: $durationSeconds 秒');
      return (path ?? _recordPath, durationSeconds);
    } catch (e) {
      debugPrint('停止录音失败: $e');
      _isRecording = false;
      return (null, 0);
    }
  }

  /// 停止录音（兼容旧代码）
  Future<String?> stopRecording() async {
    final (path, _) = await stopRecordingWithDuration();
    return path;
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.stop();
      _isRecording = false;
      _startTime = null;

      // 删除临时文件
      if (_recordPath != null && !kIsWeb) {
        final file = File(_recordPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _recordPath = null;
    } catch (e) {
      debugPrint('取消录音失败: $e');
    }
  }

  /// 获取录音时长（秒）
  int getDurationInSeconds() {
    if (_startTime == null) return 0;
    final duration = DateTime.now().difference(_startTime!);
    return duration.inSeconds;
  }

  /// 获取录音文件大小（MB）
  Future<double> getFileSizeInMB() async {
    if (_recordPath == null) return 0;

    try {
      if (kIsWeb) {
        return 0; // Web 平台无法获取文件大小
      }
      final file = File(_recordPath!);
      if (await file.exists()) {
        final bytes = await file.length();
        return bytes / (1024 * 1024);
      }
    } catch (e) {
      debugPrint('获取文件大小失败: $e');
    }
    return 0;
  }

  /// 删除录音文件
  Future<void> deleteRecording() async {
    if (_recordPath == null) return;

    try {
      if (!kIsWeb) {
        final file = File(_recordPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('删除录音文件失败: $e');
    }
    _recordPath = null;
    _startTime = null;
  }

  /// 检查平台是否支持录音
  bool get isPlatformSupported => true;

  /// 释放资源
  void dispose() {
    _recorder.dispose();
  }
}
