import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 短音频播放层
///
/// 监听 [tickStream]，每来一拍播放一个短音效（accent 或 regular）。
/// 用 1 个 [AudioPlayer] + 串行 play 队列避免重叠。
///
/// 设计：
/// - just_audio 没有"预加载短音效到内存"机制，每次 play 都重新解码。60ms 8kHz
///   短音频解码开销极低，可接受。
/// - 串行 play 队列避免两次 play 并发导致音频引擎内部冲突。
/// - just_audio 0.9.x 的 API：`setAsset(String)` + `play()`（无参），没有
///   `AudioContext` / `ReleaseMode` / `AssetSource` —— 那是 audioplayers 包。
class MetronomeAudio {
  MetronomeAudio({Stream<int>? tickStream, ValueNotifier<String?>? errorSink})
      : _externalTickStream = tickStream,
        _errorSink = errorSink;

  final Stream<int>? _externalTickStream;
  final ValueNotifier<String?>? _errorSink;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<int>? _tickSub;

  bool _started = false;
  bool _disposed = false;
  Future<void> _startFuture = Future.value();
  int _beatsPerMeasure = 4;

  /// 串行 play 队列，确保不会出现两次 play() 并发。
  Future<void> _playQueue = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _playQueue.then((_) async {
      try {
        await op();
      } catch (e) {
        _emitError(e);
      }
    });
    _playQueue = next;
    return next;
  }

  void _emitError(Object e) {
    if (_disposed) return;
    final sink = _errorSink;
    if (sink is ValueNotifier<String?>) {
      sink.value = e.toString();
    }
    debugPrint('MetronomeAudio error: $e');
  }

  Future<void> start() {
    if (_disposed || _started) return _startFuture;
    _started = true;
    _startFuture = _doStart();
    return _startFuture;
  }

  Future<void> _doStart() async {
    try {
      final stream = _externalTickStream;
      if (stream != null && _tickSub == null) {
        _tickSub = stream.listen(_onTick);
      }
    } catch (e, st) {
      _emitError(e);
      debugPrintStack(stackTrace: st);
    }
  }

  void _onTick(int beatIndex) {
    if (_disposed) return;
    final isAccent = beatIndex % _beatsPerMeasure == 0;
    // 音色交替：偶数 tick 用音色1，奇数 tick 用音色2
    final variant = (beatIndex ~/ _beatsPerMeasure) % 2;
    final assetPath = isAccent
        ? (variant == 0
            ? 'audio/metronome/accent_1.wav'
            : 'audio/metronome/accent_2.wav')
        : (variant == 0
            ? 'audio/metronome/regular_1.wav'
            : 'audio/metronome/regular_2.wav');

    _enqueue(() async {
      try {
        await _player.stop();
        await _player.setAsset(assetPath);
        await _player.play();
      } catch (e) {
        _emitError(e);
      }
    });
  }

  Future<void> stop() async {
    _tickSub?.cancel();
    _tickSub = null;
    try {
      await _player.stop();
    } catch (_) {}
    _started = false;
  }

  void setBeatsPerMeasure(int beats) {
    _beatsPerMeasure = beats;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _tickSub?.cancel();
    _tickSub = null;
    try {
      await _player.dispose();
    } catch (_) {}
  }
}