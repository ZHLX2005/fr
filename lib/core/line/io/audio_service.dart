import 'dart:async';
import 'package:just_audio/just_audio.dart';

/// 音频与游戏同步器 — 定期校准 Stopwatch 消除漂移
class _AudioSyncGuard {
  final AudioPlayer player;
  final Stopwatch stopwatch;
  Timer? _timer;
  int _lastCorrectionTarget = -1;

  _AudioSyncGuard({required this.player, required this.stopwatch});

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _correct());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _correct() {
    final audioMs = player.position.inMilliseconds;
    final swMs = stopwatch.elapsedMilliseconds;
    final diff = audioMs - swMs;
    if (diff.abs() > 50 && _lastCorrectionTarget != swMs) {
      player.seek(Duration(milliseconds: swMs));
      _lastCorrectionTarget = swMs;
    }
  }

  void dispose() {
    stop();
  }
}

/// 音频服务 — 管理音频播放、完成回调、同步校准
class AudioService {
  final Stopwatch gameStopwatch;
  final String audioPath;
  AudioPlayer? _player;
  StreamSubscription? _completionSub;
  _AudioSyncGuard? _syncGuard;

  /// 音频播放完成回调
  void Function()? onCompletion;

  AudioService({
    required this.gameStopwatch,
    required this.audioPath,
  });

  Future<void> init() async {
    _player = AudioPlayer();
    if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
      await _player!.setUrl(audioPath);
    } else {
      await _player!.setAsset(audioPath);
    }
  }

  void play() {
    _player?.play();
    _completionSub?.cancel();
    _completionSub = _player?.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        onCompletion?.call();
      }
    });
    if (_player != null) {
      _syncGuard?.dispose();
      _syncGuard = _AudioSyncGuard(player: _player!, stopwatch: gameStopwatch);
      _syncGuard!.start();
    }
  }

  void pause() {
    _syncGuard?.stop();
    _player?.pause();
  }

  void seek(Duration position) {
    _player?.seek(position);
  }

  void dispose() {
    _completionSub?.cancel();
    _syncGuard?.dispose();
    _player?.dispose();
    _player = null;
  }
}
