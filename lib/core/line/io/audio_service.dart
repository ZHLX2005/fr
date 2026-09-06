import 'dart:async';
import 'dart:io' show File;

import 'package:just_audio/just_audio.dart';

import '../domain/constants.dart';

/// 音频服务 — 播放 BGM；[positionMs] 作为游戏权威时钟源。
class AudioService {
  final String audioPath;
  AudioPlayer? _player;
  StreamSubscription? _completionSub;
  double _volume = lineDefaultBgmVolume;

  /// 音频播放完成回调
  void Function()? onCompletion;

  AudioService({required this.audioPath, double? volume}) {
    if (volume != null) _volume = volume.clamp(0.0, 1.0);
  }

  /// 当前播放进度（ms）。未就绪时返回 null。
  int? get positionMs {
    final p = _player;
    if (p == null) return null;
    return p.position.inMilliseconds;
  }

  bool get isReady => _player != null;

  double get volume => _volume;

  Future<void> init() async {
    _player = AudioPlayer();
    if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
      await _player!.setUrl(audioPath);
    } else {
      final file = File(audioPath);
      if (await file.exists()) {
        await _player!.setFilePath(audioPath);
      } else {
        await _player!.setAsset(audioPath);
      }
    }
    await _player!.setVolume(_volume);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _player?.setVolume(_volume);
  }

  void play() {
    _player?.play();
    _completionSub?.cancel();
    _completionSub = _player?.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        onCompletion?.call();
      }
    });
  }

  void pause() {
    _player?.pause();
  }

  void seek(Duration position) {
    _player?.seek(position);
  }

  void dispose() {
    _completionSub?.cancel();
    _player?.dispose();
    _player = null;
  }
}
