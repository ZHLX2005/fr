// lib/services/metronome/metronome_service_io.dart
//
// Native (Android) 实现 —— 使用 dart:ffi + package:ffi 调用 libmetronome.so。
// 整个 app 生命周期内**只有一个 Oboe stream 实例**，由 [MetronomeService] 持有。
// 这避免了之前"双 provider 实例各自关一次 stream"导致的卡死问题，以及
// "controller dispose 时关 stream → sample slot 跟着没了"导致的跨页配置丢失。
//
// 使用：
// ```dart
// MetronomeService.instance.tickStream.listen((beat) => ...);
// MetronomeService.instance.setBpm(120);
// MetronomeService.instance.play();
// ```
//
// ## 生命周期（省电约束，勿回退）
//
// Oboe 流是 LowLatency + Exclusive 输出流 —— 最耗电的音频模式，且
// `init_audio()` 里 `requestStart()` 之后即使 `pause()` 了回调仍在跑
// （只是输出静音）。音频 HAL 常驻会阻止 CPU 进入深度睡眠，是系统判定
// 「后台高耗电」的主因之一。因此本类遵守两条纪律：
//
// 1. **按需初始化**：构造函数不再预热。所有会碰流的方法
//    （[setBpm] / [setBeatsPerBar] / [setBeatAccentLevel] / [play]）
//    内部自动 `ensureReady()`，未就绪时调用不会抛错。
// 2. **空闲自关**：[pause] 后 [kMetronomeIdleShutdownDelay] 内没有任何
//    [play]，就真正 `shutdown()` 掉流并释放音频设备。
//
// 采样槽（woodfish 等）**不受 shutdown 影响** —— cpp 端 `shutdown_audio()`
// 刻意不释放 `gSamples`，且 [loadSample] 在流未就绪时会记账、待首次
// `ensureReady()` 时回放，所以调用顺序无关。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'const_metronome_service.dart';

/// C 端 Tick 回调签名：void(int beatIndex)
typedef _NativeTick = Void Function(Int32);

/// C 函数指针签名
typedef _InitAudioNative = Void Function(Double);
typedef _InitAudioDart = void Function(double);

typedef _ShutdownAudioNative = Void Function();
typedef _ShutdownAudioDart = void Function();

typedef _PlayNative = Void Function();
typedef _PlayDart = void Function();

typedef _PauseNative = Void Function();
typedef _PauseDart = void Function();

typedef _SetBpmNative = Void Function(Double);
typedef _SetBpmDart = void Function(double);

typedef _SetBeatsPerBarNative = Void Function(Int32);
typedef _SetBeatsPerBarDart = void Function(int);

typedef _SetBeatAccentLevelNative = Void Function(Int32, Int32);
typedef _SetBeatAccentLevelDart = void Function(int, int);

typedef _SetTickCallbackNative = Void Function(
    Pointer<NativeFunction<_NativeTick>>);
typedef _SetTickCallbackDart = void Function(
    Pointer<NativeFunction<_NativeTick>>);

typedef _LoadSampleNative = Int32 Function(Int32, Pointer<Uint8>);
typedef _LoadSampleDart = int Function(int, Pointer<Uint8>);

typedef _ClearSampleNative = Void Function(Int32);
typedef _ClearSampleDart = void Function(int);

class MetronomeService {
  MetronomeService._();

  /// 全局唯一实例。整个进程共享同一份 Oboe stream 和 sample slot。
  static final MetronomeService instance = MetronomeService._();

  static DynamicLibrary get _lib => Platform.isAndroid
      ? DynamicLibrary.open('libmetronome.so')
      : (throw UnsupportedError('Only Android is supported for metronome'));

  static final _initAudio =
      _lib.lookupFunction<_InitAudioNative, _InitAudioDart>('init_audio');
  static final _shutdownAudio = _lib
      .lookupFunction<_ShutdownAudioNative, _ShutdownAudioDart>('shutdown_audio');
  static final _play =
      _lib.lookupFunction<_PlayNative, _PlayDart>('play_metronome');
  static final _pause =
      _lib.lookupFunction<_PauseNative, _PauseDart>('pause_metronome');
  static final _setBpm =
      _lib.lookupFunction<_SetBpmNative, _SetBpmDart>('set_bpm');
  static final _setBeatsPerBar =
      _lib.lookupFunction<_SetBeatsPerBarNative, _SetBeatsPerBarDart>(
          'set_beats_per_bar');
  static final _setBeatAccentLevel =
      _lib.lookupFunction<_SetBeatAccentLevelNative, _SetBeatAccentLevelDart>(
          'set_beat_accent_level');
  static final _loadSample =
      _lib.lookupFunction<_LoadSampleNative, _LoadSampleDart>('load_sample');
  static final _clearSample =
      _lib.lookupFunction<_ClearSampleNative, _ClearSampleDart>('clear_sample');

  NativeCallable<_NativeTick>? _tickCallable;
  final StreamController<int> _tickStreamController =
      StreamController<int>.broadcast();

  /// 拍点流。每次 C++ 推一帧过来就 +1。
  /// 注意：native 传来的 `beatIndex` 是 `beat % beatsPerBar` 已经是 0..beatsPerBar-1。
  Stream<int> get tickStream => _tickStreamController.stream;

  bool _initialized = false;

  /// Oboe 流当前是否已打开。仅供诊断/测试读取。
  bool get isInitialized => _initialized;

  bool _playing = false;
  Timer? _idleTimer;

  /// 流未就绪时挂起的采样路径（level -> path），[ensureReady] 后回放。
  ///
  /// 必要性：cpp 的 `load_sample()` 在 `gMetronome == null` 时**直接 return 0**，
  /// 所以冷启动时 `SampleLoader.restoreAtStartup()` 若早于音频流打开就会静默失效
  /// （木鱼音色丢失，即历史 fr #2 bug）。记账回放让调用顺序不再重要。
  final Map<int, String> _pendingSamples = {};

  /// 初始化 Oboe 音频流。多次调用只生效一次。
  ///
  /// 同时把 Dart 函数包成 native 可调用的 callable 注入 C++，使后续每次拍点触发
  /// 时 C++ 通过函数指针回调到 Dart，Flutter 派发到 UI isolate。
  ///
  /// **不要**在 app 冷启动路径上主动调用（见文件头「生命周期」）——
  /// 由 [setBpm] / [play] 等真正需要发声的调用自动触发。
  void ensureReady({double bpm = 120.0}) {
    if (_initialized) return;
    _initAudio(bpm);
    _tickCallable = NativeCallable<_NativeTick>.listener(_onNativeTick);
    _lib.lookupFunction<_SetTickCallbackNative, _SetTickCallbackDart>(
        'set_tick_callback')(_tickCallable!.nativeFunction);
    _initialized = true;

    // 回放流未起时记账的采样挂载
    if (_pendingSamples.isNotEmpty) {
      final pending = Map<int, String>.from(_pendingSamples);
      _pendingSamples.clear();
      for (final entry in pending.entries) {
        _loadSampleNow(entry.key, entry.value);
      }
    }
  }

  /// 流未就绪时先 init，再执行 [action]。
  void _withStream(void Function() action) {
    ensureReady();
    action();
  }

  void _onNativeTick(int beatIndex) {
    if (_tickStreamController.isClosed) return;
    _tickStreamController.add(beatIndex);
  }

  /// 设置 BPM（范围由 cpp 端限制 20..300）。流未就绪时自动打开。
  void setBpm(double bpm) => _withStream(() => _setBpm(bpm));

  /// 设置每小节拍数。流未就绪时自动打开。
  void setBeatsPerBar(int beats) => _withStream(() => _setBeatsPerBar(beats));

  /// 设置某拍的重音级别（0=弱, 1=次强, 2=强）。流未就绪时自动打开。
  void setBeatAccentLevel(int beatIndex, int level) =>
      _withStream(() => _setBeatAccentLevel(beatIndex, level));

  /// 开始播放（不阻塞）。流未就绪时自动打开，并撤销待执行的空闲自关。
  void play() {
    _cancelIdleShutdown();
    _playing = true;
    _withStream(_play);
  }

  /// 暂停。流未就绪时是 no-op（不为了"暂停"去打开音频设备）。
  ///
  /// 暂停后安排一次空闲自关：若 [kMetronomeIdleShutdownDelay] 内没有新的
  /// [play]，就真正释放 Oboe 流与音频设备。
  void pause() {
    _playing = false;
    if (!_initialized) return;
    _pause();
    _scheduleIdleShutdown();
  }

  void _cancelIdleShutdown() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _scheduleIdleShutdown() {
    _cancelIdleShutdown();
    _idleTimer = Timer(kMetronomeIdleShutdownDelay, () {
      _idleTimer = null;
      if (_playing) return; // 期间又播了
      if (!_initialized) return;
      shutdown();
    });
  }

  /// 把 WAV 挂载到指定 accent 档位（0=弱, 1=次强, 2=强）。
  /// **会持久保留**（即使 Oboe 流被空闲关闭）直到显式 [clearSample] 或
  /// 重新 [loadSample] 同一档。
  ///
  /// 流未就绪时先记账、返回 true，待 [ensureReady] 时回放 —— 因为 cpp 的
  /// `load_sample()` 在 `gMetronome == null` 时会失败，记账让调用顺序无关。
  bool loadSample(int level, String path) {
    if (level < 0 || level >= kMetronomeSampleLevels) return false;
    if (!_initialized) {
      _pendingSamples[level] = path;
      return true;
    }
    return _loadSampleNow(level, path);
  }

  bool _loadSampleNow(int level, String path) {
    final bytes = utf8.encode(path);
    final ptr = calloc<Uint8>(bytes.length + 1);
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      ptr[bytes.length] = 0;
      return _loadSample(level, ptr) == 1;
    } finally {
      calloc.free(ptr);
    }
  }

  /// 卸载指定档位的 WAV，恢复为合成音色。同时撤销未回放的记账。
  void clearSample(int level) {
    if (level < 0 || level >= kMetronomeSampleLevels) return;
    _pendingSamples.remove(level);
    if (!_initialized) return;
    _clearSample(level);
  }

  /// 关闭 Oboe 流并释放 tick callable，让音频设备可以下电。
  ///
  /// 由 [pause] 后的空闲计时器自动调用，也用于测试。**不会**丢失采样挂载
  /// （cpp 端刻意不释放 `gSamples`），下次 [play] / [setBpm] 会自动重开流。
  Future<void> shutdown() async {
    if (!_initialized) return;
    _cancelIdleShutdown();
    _playing = false;
    _shutdownAudio();
    _tickCallable?.close();
    _tickCallable = null;
    _initialized = false;
  }

  /// 测试钩子：reset 全部状态（关闭流 + 释放 callback）。
  Future<void> resetForTest() => shutdown();
}
