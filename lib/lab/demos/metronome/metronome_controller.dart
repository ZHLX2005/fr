import 'dart:async';

import 'package:flutter/foundation.dart';

import 'const_metronome.dart';
import 'ffi_bindings.dart';

/// 节拍器控制器（Oboe FFI 版）
///
/// 修过的根本问题（与上一版同）：
/// 1. **状态机翻转与音频就绪解耦**。start/stop 立即翻 `_isPlaying`，C++ play/pause
///    fire-and-forget。
/// 2. **拍号变更零延迟**。setBeatsPerBar 直接调 FFI，C++ 在下一个 sample 周期
///    立即生效（Oboe audio callback 在后台持续跑，几 ms 之内换完）。
/// 3. **视图/音频同源**。currentBeatNotifier 订阅 [MetronomeFFI.tickStream]，
///    数据来自 C++ 音频回调线程，物理上不可能漂移。
///
/// 这一版相比上一版 Timer 方案：
/// - 音频 tick 由 C++ 在 Oboe 音频线程生成，Dart 完全不参与相位。
/// - 后台运行不被冻结（Oboe 走系统 AAudio/Oboe 服务）。
/// - 单帧回调延迟 < 5ms。
class MetronomeController extends ChangeNotifier {
  MetronomeController() {
    // 构造时立即订阅 C++ 的 tick 流（Oboe 在 init 时已经在跑了，但不会 tick，
    // 因为 isPlaying=false）。订阅先建立，start() 时 C++ 立刻开始推。
    _tickSub = MetronomeFFI.tickStream.listen((beatIndex) {
      if (_disposed) return;
      currentBeatNotifier.value = beatIndex;
    });
    MetronomeFFI.init(MetronomeDefaults.defaultBpm.toDouble());
    _initialized = true;
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

  // ==================== 内部 ====================

  StreamSubscription<int>? _tickSub;
  bool _disposed = false;
  bool _initialized = false;

  // ==================== Tap Tempo ====================

  final List<DateTime> _tapTimes = [];

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tickSub?.cancel();
    _tickSub = null;
    if (_initialized) {
      MetronomeFFI.pause();
      MetronomeFFI.shutdown();
      _initialized = false;
    }
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
    MetronomeFFI.setBpm(_bpm.toDouble());
    notifyListeners();
  }

  void incrementBpm() => setBpm(_bpm + 1);
  void decrementBpm() => setBpm(_bpm - 1);

  void setBeatPattern(BeatPattern pattern) {
    if (_beatPattern == pattern) return;
    _beatPattern = pattern;
    MetronomeFFI.setBeatsPerBar(pattern.beatsPerMeasure);
    // 拍号变了，立即归零（视觉马上反映新拍号的第一拍即将开始）
    currentBeatNotifier.value = 0;
    notifyListeners();
  }

  Future<void> togglePlay() => _isPlaying ? stop() : start();

  Future<void> start() async {
    if (_isPlaying || _disposed || !_initialized) return;
    _isPlaying = true;
    notifyListeners();
    MetronomeFFI.play();
  }

  Future<void> stop() async {
    if (!_isPlaying || _disposed) return;
    _isPlaying = false;
    currentBeatNotifier.value = 0;
    notifyListeners();
    MetronomeFFI.pause();
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