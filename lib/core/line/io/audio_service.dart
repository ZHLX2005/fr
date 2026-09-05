import 'dart:async';
import 'dart:io' show File;

import 'package:just_audio/just_audio.dart';

/// 音频服务 — 播放 BGM；[positionMs] 作为游戏权威时钟源。
class AudioService {
  final String audioPath;
  AudioPlayer? _player;
  StreamSubscription? _completionSub;

  /// 音频播放完成回调
  void Function()? onCompletion;

  AudioService({required this.audioPath});

  /// 当前播放进度（ms）。未就绪时返回 null。
  int? get positionMs {
    final p = _player;
    if (p == null) return null;
    return p.position.inMilliseconds;
  }

  bool get isReady => _player != null;

  Future<void> init() async {
    _player = AudioPlayer();
    if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
      await _player!.setUrl(audioPath);
      return;
    }
    final file = File(audioPath);
    if (await file.exists()) {
      await _player!.setFilePath(audioPath);
      return;
    }
    await _player!.setAsset(audioPath);
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
