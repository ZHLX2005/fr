import 'dart:async';

import 'package:flutter/foundation.dart';

import 'const_metronome.dart';
import 'metronome_audio.dart';
import 'tick_scheduler.dart';

/// 节拍器控制器
///
/// 修过的三个根本问题：
///
/// 1. **状态机翻转与音频就绪解耦**。`start` / `stop` / `pause` 同步翻 `_isPlaying`
///    + notifyListeners；scheduler.start() / audio.start() fire-and-forget，不
///    影响 UI 意图层。再点一下 start 不会再"和上一帧的 start 撞车"。
///
/// 2. **拍号变更零延迟**。setBeatPattern 同步更新内部 + 重启 scheduler Timer +
///    audio 的 beatsPerMeasure。没有"重生成 WAV → 写文件 → setFilePath"这条
///    慢链。
///
/// 3. **视图同步走 tickStream**。currentBeatNotifier 直接订阅 scheduler.tickStream，
///    不再从音频 positionStream 反推。视觉和音频是同一个事件源，绝不会错位。
class MetronomeController extends ChangeNotifier {
  MetronomeController({
    ITickScheduler? scheduler,
    MetronomeAudio? audio,
  })  : _scheduler = scheduler ?? PeriodicTickScheduler(),
        _audio = audio ?? MetronomeAudio() {
    // 订阅 scheduler 的 tick 流，驱动 currentBeatNotifier
    _tickSub = _scheduler.tickStream.listen((beatIndex) {
      if (_disposed) return;
      currentBeatNotifier.value = beatIndex;
    });
  }

  // ==================== 状态 ====================

  int _bpm = MetronomeDefaults.defaultBpm;
  int get bpm => _bpm;

  BeatPattern _beatPattern = MetronomePresets.defaultPattern;
  BeatPattern get beatPattern => _beatPattern;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  final ValueNotifier<int> currentBeatNotifier = ValueNotifier(0);
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  // ==================== 依赖 ====================

  final ITickScheduler _scheduler;
  final MetronomeAudio _audio;
  StreamSubscription<int>? _tickSub;

  // ==================== Tap Tempo ====================

  final List<DateTime> _tapTimes = [];

  // ==================== 生命周期 ====================

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tickSub?.cancel();
    _tickSub = null;
    // scheduler/audio dispose 是 fire-and-forget，避免 dispose 卡住
    _scheduler.dispose();
    _audio.dispose();
    currentBeatNotifier.dispose();
    errorNotifier.dispose();
    super.dispose();
  }

  // ==================== 对外操作 ====================

  void setBpm(int newBpm) {
    final clamped =
        newBpm.clamp(MetronomeDefaults.minBpm, MetronomeDefaults.maxBpm);
    if (_bpm == clamped) return;
    _bpm = clamped;
    _scheduler.setBpm(_bpm);
    notifyListeners();
  }

  void incrementBpm() => setBpm(_bpm + 1);
  void decrementBpm() => setBpm(_bpm - 1);

  void setBeatPattern(BeatPattern pattern) {
    if (_beatPattern == pattern) return;
    _beatPattern = pattern;
    final beats = pattern.beatsPerMeasure;
    _scheduler.setBeatsPerMeasure(beats);
    _audio.setBeatsPerMeasure(beats);
    // 拍号变了，立即归零（让 UI 显示"新拍号的第一拍即将开始"）
    currentBeatNotifier.value = 0;
    notifyListeners();
  }

  Future<void> togglePlay() => _isPlaying ? stop() : start();

  Future<void> start() async {
    if (_isPlaying || _disposed) return;
    _isPlaying = true;
    notifyListeners();
    // fire-and-forget：意图已生效，音频/scheduler 不阻塞状态机
    _scheduler.start();
    _audio.start();
  }

  Future<void> stop() async {
    if (!_isPlaying || _disposed) return;
    _isPlaying = false;
    currentBeatNotifier.value = 0;
    notifyListeners();
    _scheduler.stop();
    _audio.stop();
  }

  Future<void> pause() => stop();

  void tap() {
    final now = DateTime.now();

    if (_tapTimes.isNotEmpty) {
      final gap = now.difference(_tapTimes.last).inMilliseconds;
      if (gap > MetronomeDefaults.tapTempoMaxIntervalMs) {
        _tapTimes.clear();
      }
    }

    _tapTimes.add(now);
    if (_tapTimes.length > MetronomeDefaults.tapTempoHistorySize) {
      _tapTimes.removeAt(0);
    }
    if (_tapTimes.length < 2) return;

    final intervals = <int>[];
    for (int i = 1; i < _tapTimes.length; i++) {
      intervals.add(_tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds);
    }
    final avg = intervals.reduce((a, b) => a + b) / intervals.length;
    if (avg < MetronomeDefaults.tapTempoMinIntervalMs) return;

    final calc = (60000 / avg).round();
    if (calc < MetronomeDefaults.minBpm || calc > MetronomeDefaults.maxBpm) {
      return;
    }
    setBpm(calc);
  }

  void resetTapTempo() {
    _tapTimes.clear();
  }
}