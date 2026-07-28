import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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

/// 共享的 Oboe 节拍器音频引擎。
///
/// 整个 app 生命周期内**只有一个 Oboe stream 实例**，由 [MetronomeService] 持有。
/// 这避免了之前"双 provider 实例各自关一次 stream"导致的卡死问题，以及
/// "controller dispose 时关 stream → sample slot 跟着没了"导致的跨页配置丢失。
///
/// 使用：
/// ```dart
/// await MetronomeService.instance.ensureReady();
/// MetronomeService.instance.tickStream.listen((beat) => ...);
/// MetronomeService.instance.setBpm(120);
/// ```
///
/// 这个类**不调用 shutdown**。Oboe stream 跟随 app 进程。如果未来需要支持
/// 真正的开关机（如省电模式），由 app lifecycle 钩子显式调用。
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

  /// 初始化 Oboe 音频流。多次调用只生效一次。
  ///
  /// 同时把 Dart 函数包成 native 可调用的 callable 注入 C++，使后续每次拍点触发
  /// 时 C++ 通过函数指针回调到 Dart，Flutter 派发到 UI isolate。
  void ensureReady({double bpm = 120.0}) {
    if (_initialized) return;
    _initAudio(bpm);
    _tickCallable = NativeCallable<_NativeTick>.listener(_onNativeTick);
    _lib.lookupFunction<_SetTickCallbackNative, _SetTickCallbackDart>(
        'set_tick_callback')(_tickCallable!.nativeFunction);
    _initialized = true;
  }

  void _onNativeTick(int beatIndex) {
    if (_tickStreamController.isClosed) return;
    _tickStreamController.add(beatIndex);
  }

  /// 设置 BPM（范围由 cpp 端限制 20..300）。
  void setBpm(double bpm) {
    _ensureChecked();
    _setBpm(bpm);
  }

  /// 设置每小节拍数。
  void setBeatsPerBar(int beats) {
    _ensureChecked();
    _setBeatsPerBar(beats);
  }

  /// 设置某拍的重音级别（0=弱, 1=次强, 2=强）。
  void setBeatAccentLevel(int beatIndex, int level) {
    _ensureChecked();
    _setBeatAccentLevel(beatIndex, level);
  }

  /// 开始播放（不阻塞）。
  void play() {
    _ensureChecked();
    _play();
  }

  /// 暂停。
  void pause() {
    _ensureChecked();
    _pause();
  }

  /// 把 WAV 挂载到指定 accent 档位（0=弱, 1=次强, 2=强）。
  /// **会持久保留**直到显式 [clearSample] 或重新 [loadSample] 同一档。
  bool loadSample(int level, String path) {
    if (level < 0 || level > 2) return false;
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

  /// 卸载指定档位的 WAV，恢复为合成音色。
  void clearSample(int level) {
    if (level < 0 || level > 2) return;
    _clearSample(level);
  }

  /// 关闭 Oboe 流并释放 tick callable。一般不要调用 — stream 跟随 app 进程。
  /// 仅在需要彻底卸载（如 logout / 测试）时使用。
  Future<void> shutdown() async {
    if (!_initialized) return;
    _shutdownAudio();
    _tickCallable?.close();
    _tickCallable = null;
    _initialized = false;
  }

  void _ensureChecked() {
    if (!_initialized) {
      throw StateError(
        'MetronomeService: stream not initialized. '
        'Call MetronomeService.instance.ensureReady() first.',
      );
    }
  }

  /// 测试钩子：reset 全部状态（关闭流 + 释放 callback）。
  Future<void> resetForTest() => shutdown();
}