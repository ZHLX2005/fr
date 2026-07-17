import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'const_metronome.dart';
import 'beat_buffer_generator.dart';

/// 节拍器控制器
/// 管理节拍器的状态和音频播放
class MetronomeController extends ChangeNotifier {
  // ==================== 状态 ====================

  int _bpm = MetronomeDefaults.defaultBpm;
  int get bpm => _bpm;

  BeatPattern _beatPattern = MetronomePresets.defaultPattern;
  BeatPattern get beatPattern => _beatPattern;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  int _currentBeatIndex = 0;
  int get currentBeatIndex => _currentBeatIndex;

  // ==================== 音频引擎 ====================

  // 使用 just_audio 实现
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 临时文件路径（用于播放 PCM 数据）
  String? _tempWavPath;

  // 视觉定时器
  Timer? _visualTimer;

  // Tap Tempo 相关
  final List<DateTime> _tapTimes = [];

  // ==================== 初始化 ====================

  MetronomeController() {
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // 设置播放器参数
    await _audioPlayer.setLoopMode(LoopMode.all);
    await _audioPlayer.setVolume(1.0);
  }

  // ==================== 控制方法 ====================

  /// 设置 BPM
  void setBpm(int newBpm) {
    final clampedBpm = newBpm.clamp(MetronomeDefaults.minBpm, MetronomeDefaults.maxBpm);
    if (_bpm == clampedBpm) return;

    _bpm = clampedBpm;
    if (_isPlaying) {
      // 重新启动以应用新 BPM
      _restartPlayback();
    }
    notifyListeners();
  }

  /// 增加 BPM（每次 +1）
  void incrementBpm() {
    setBpm(_bpm + 1);
  }

  /// 减少 BPM（每次 -1）
  void decrementBpm() {
    setBpm(_bpm - 1);
  }

  /// 设置节拍模式
  void setBeatPattern(BeatPattern pattern) {
    if (_beatPattern == pattern) return;

    _beatPattern = pattern;
    if (_isPlaying) {
      _restartPlayback();
    }
    notifyListeners();
  }

  /// 切换播放/暂停
  Future<void> togglePlay() async {
    if (_isPlaying) {
      await stop();
    } else {
      await start();
    }
  }

  /// 开始播放
  Future<void> start() async {
    if (_isPlaying) return;

    try {
      // 生成节拍缓冲区（WAV 格式）
      final buffer = BeatBufferGenerator.generate(
        bpm: _bpm,
        beatPattern: _beatPattern,
      );

      // 将 WAV 数据写入临时文件
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _tempWavPath = '${tempDir.path}/metronome_$timestamp.wav';
      final tempFile = File(_tempWavPath!);
      await tempFile.writeAsBytes(buffer);

      // 使用 just_audio 播放临时文件
      await _audioPlayer.setFilePath(_tempWavPath!);
      await _audioPlayer.play();

      _isPlaying = true;
      _currentBeatIndex = 0;
      _startVisualTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('Metronome start error: $e');
    }
  }

  /// 停止播放
  Future<void> stop() async {
    if (!_isPlaying) return;

    _visualTimer?.cancel();
    _visualTimer = null;

    await _audioPlayer.stop();
    _isPlaying = false;
    _currentBeatIndex = 0;
    notifyListeners();
  }

  /// 暂停播放
  Future<void> pause() async {
    if (!_isPlaying) return;

    _visualTimer?.cancel();
    await _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  /// Tap Tempo - 记录点击
  void tap() {
    final now = DateTime.now();

    // 清理过旧的点击（超过 3 秒）
    if (_tapTimes.isNotEmpty) {
      final lastTap = _tapTimes.last;
      if (now.difference(lastTap).inMilliseconds > MetronomeDefaults.tapTempoMaxIntervalMs) {
        _tapTimes.clear();
      }
    }

    // 添加新点击
    _tapTimes.add(now);

    // 保持固定数量的历史记录
    if (_tapTimes.length > MetronomeDefaults.tapTempoHistorySize) {
      _tapTimes.removeAt(0);
    }

    // 计算 BPM（至少需要 2 次点击）
    if (_tapTimes.length >= 2) {
      final intervals = <int>[];
      for (int i = 1; i < _tapTimes.length; i++) {
        intervals.add(_tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds);
      }

      // 计算平均间隔
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;

      // 转换为 BPM
      final calculatedBpm = (60000 / avgInterval).round();

      // 验证 BPM 范围
      if (calculatedBpm >= MetronomeDefaults.minBpm &&
          calculatedBpm <= MetronomeDefaults.maxBpm) {
        _bpm = calculatedBpm;
        notifyListeners();

        // 如果正在播放，重启以应用新 BPM
        if (_isPlaying) {
          _restartPlayback();
        }
      }
    }
  }

  /// 重置 Tap Tempo 历史
  void resetTapTempo() {
    _tapTimes.clear();
  }

  // ==================== 私有方法 ====================

  /// 启动视觉定时器
  void _startVisualTimer() {
    _visualTimer?.cancel();
    final intervalMs = (60000 / _bpm).round();
    _visualTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _onBeat(),
    );
  }

  /// 节拍触发回调
  void _onBeat() {
    _currentBeatIndex = (_currentBeatIndex + 1) % _beatPattern.beatsPerMeasure;
    notifyListeners();
  }

  /// 重启播放
  Future<void> _restartPlayback() async {
    await stop();
    await start();
  }

  // ==================== 生命周期 ====================

  @override
  void dispose() {
    _visualTimer?.cancel();
    _audioPlayer.dispose();
    // 清理临时文件
    if (_tempWavPath != null) {
      final file = File(_tempWavPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    super.dispose();
  }
}
