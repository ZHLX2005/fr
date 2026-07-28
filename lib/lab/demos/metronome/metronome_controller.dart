import 'dart:async';

import 'package:flutter/foundation.dart';

import 'const_metronome.dart';
import 'ffi_bindings.dart';
import 'sample_loader.dart';

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
    // 推送默认拍号的重音级别到 cpp（cpp 默认只把 index 0 设为 accent，碰上
    // 6/8、5/4、7/8 这种多强拍/次强拍的模式需重新设）
    final defaultPattern = MetronomePresets.defaultPattern;
    MetronomeFFI.setBeatsPerBar(defaultPattern.beatsPerMeasure);
    for (int i = 0; i < defaultPattern.beatsPerMeasure; i++) {
      final dartLevel = defaultPattern.getAccentLevel(i);
      final cppLevel = switch (dartLevel) {
        AccentLevel.weak => 0,
        AccentLevel.medium => 1,
        AccentLevel.accent => 2,
      };
      MetronomeFFI.setBeatAccentLevel(i, cppLevel);
    }
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

  // ==================== Sound Customisation ====================

  /// Sound profile identifiers for each accent level.
  /// 0 = synth (default, always available)
  /// 1 = woodfish (from asset WAV)
  static const int soundSynth = 0;
  static const int soundWoodfish = 1;

  final List<int> _soundIds = [0, 0, 0]; // per level [weak, medium, accent]

  /// The sound profile id (e.g. 0=synth, 1=woodfish) for [level].
  int soundForLevel(int level) =>
      level >= 0 && level < _soundIds.length ? _soundIds[level] : 0;

  /// Mount/unmount a custom sound for the given accent [level].
  ///
  /// - [soundId] 0 → synth (default, clears any loaded sample)
  /// - [soundId] 1 → woodfish (extracts the built-in WAV and loads it)
  ///
  /// Returns true if the mount succeeded. A failure (e.g. file IO) keeps the
  /// previous setting.
  Future<bool> setSoundForLevel(int level, int soundId) async {
    if (level < 0 || level > 2) return false;
    if (soundId < 0 || soundId > 1) return false;
    if (_soundIds[level] == soundId) return true;

    final ok = soundId == soundSynth
        ? _mountSynth(level)
        : await _mountWoodfish(level);

    if (ok) {
      _soundIds[level] = soundId;
      notifyListeners();
    }
    return ok;
  }

  bool _mountSynth(int level) {
    MetronomeFFI.clearSample(level);
    return true;
  }

  Future<bool> _mountWoodfish(int level) async {
    try {
      final path = await SampleLoader.materializeAsset(
        'assets/audio/woodfish.wav',
      );
      return MetronomeFFI.loadSample(level, path);
    } catch (_) {
      return false;
    }
  }

  /// Reset all levels back to synth (default).
  Future<void> resetAllSounds() async {
    for (var level = 0; level < 3; level++) {
      _mountSynth(level);
      _soundIds[level] = 0;
    }
    notifyListeners();
  }

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
    // 把每拍的重音级别推给 cpp —— 让强弱次强音色差别真正听得出来。
    // 映射：Dart AccentLevel (accent=0, medium=1, weak=2) → cpp 音色索引
    // (0=weak, 1=medium, 2=accent)
    for (int i = 0; i < pattern.beatsPerMeasure; i++) {
      final dartLevel = pattern.getAccentLevel(i);
      final cppLevel = switch (dartLevel) {
        AccentLevel.weak => 0,
        AccentLevel.medium => 1,
        AccentLevel.accent => 2,
      };
      MetronomeFFI.setBeatAccentLevel(i, cppLevel);
    }
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