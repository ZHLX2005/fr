import '../domain/constants.dart';
import 'judge_service.dart';

/// 帧统一游戏时钟：优先音频进度，并在采样间隙用墙钟外推。
class GameClock {
  GameClock({this.inputOffsetMs = 0});

  int inputOffsetMs;

  int? _lastAudioMs;
  int _lastWallMs = 0;
  final Stopwatch _wall = Stopwatch();
  final Stopwatch _fallback = Stopwatch();

  void start() {
    _wall
      ..reset()
      ..start();
    _fallback
      ..reset()
      ..start();
    _lastAudioMs = null;
    _lastWallMs = 0;
  }

  void stop() {
    _wall.stop();
    _fallback.stop();
  }

  void reset() {
    _wall.reset();
    _fallback.reset();
    _lastAudioMs = null;
    _lastWallMs = 0;
  }

  int sample(int? audioMs) {
    final wall = _wall.isRunning ? _wall.elapsedMilliseconds : 0;
    if (audioMs != null) {
      if (_lastAudioMs != null && audioMs + 80 < _lastAudioMs!) {
        _lastAudioMs = audioMs;
        _lastWallMs = wall;
      } else if (_lastAudioMs == null || audioMs >= _lastAudioMs!) {
        _lastAudioMs = audioMs;
        _lastWallMs = wall;
      }
      final extrapolated = _lastAudioMs! + (wall - _lastWallMs).clamp(0, 80);
      return extrapolated + inputOffsetMs;
    }
    if (!_fallback.isRunning) _fallback.start();
    return _fallback.elapsedMilliseconds + inputOffsetMs;
  }
}

JudgeResultLabel worseLabel(JudgeResultLabel a, JudgeResultLabel b) {
  const order = [
    JudgeResultLabel.perfect,
    JudgeResultLabel.great,
    JudgeResultLabel.good,
    JudgeResultLabel.miss,
  ];
  return order.indexOf(a) >= order.indexOf(b) ? a : b;
}

int expectedHoldTicks(int holdDurationMs) {
  if (holdDurationMs <= 0) return 0;
  return (holdDurationMs / holdTickIntervalMs).floor().clamp(0, 64);
}

/// 合成头/身为一次最终判定（[tail] 保留参数兼容，机制上 Hold 无尾判，应传 null）
JudgeResult composeHoldResult({
  required JudgeResult head,
  required int ticksHit,
  required int ticksExpected,
  required JudgeResult? tail,
  required double timingScale,
}) {
  var label = head.label;
  var signed = head.signedDiffMs;

  if (ticksExpected > 0) {
    final ratio = ticksHit / ticksExpected;
    if (ratio < 0.5) {
      label = worseLabel(label, JudgeResultLabel.miss);
    } else if (ratio < 0.85) {
      label = worseLabel(label, JudgeResultLabel.good);
    } else if (ratio < 1.0) {
      label = worseLabel(label, JudgeResultLabel.great);
    }
  }

  // 机制无尾判：忽略 tail（即使传入也不并入）
  return judgeFromLabel(label, timingScale, signedDiffMs: signed);
}
