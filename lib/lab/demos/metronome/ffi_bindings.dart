import 'dart:async';
import 'dart:ffi';
import 'dart:io';

/// C 端 Tick 回调签名：void(int beatIndex)
typedef _NativeTick = Void Function(Int32);
typedef _DartTick = void Function(int);

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

typedef _SetUseAccentTickNative = Void Function(Bool);
typedef _SetUseAccentTickDart = void Function(bool);

typedef _SetBeatAccentLevelNative = Void Function(Int32, Int32);
typedef _SetBeatAccentLevelDart = void Function(int, int);

typedef _SetTickCallbackNative = Void Function(
    Pointer<NativeFunction<_NativeTick>>);
typedef _SetTickCallbackDart = void Function(
    Pointer<NativeFunction<_NativeTick>>);

/// Metronome FFI Bridge
///
/// 在 C++ 音频线程的 onAudioReady 回调里，会调用 [TickCallback] 通知当前拍号。
/// Dart 端订阅这条流，UI 闪指示器、tap tempo 都可以基于这条流。
class MetronomeFFI {
  static final DynamicLibrary _lib = Platform.isAndroid
      ? DynamicLibrary.open("libmetronome.so")
      : throw UnsupportedError("Only Android is supported");

  static final _initAudio =
      _lib.lookupFunction<_InitAudioNative, _InitAudioDart>('init_audio');
  static final _shutdownAudio = _lib
      .lookupFunction<_ShutdownAudioNative, _ShutdownAudioDart>('shutdown_audio');
  static final _play = _lib.lookupFunction<_PlayNative, _PlayDart>('play_metronome');
  static final _pause = _lib.lookupFunction<_PauseNative, _PauseDart>('pause_metronome');
  static final _setBpm =
      _lib.lookupFunction<_SetBpmNative, _SetBpmDart>('set_bpm');
  static final _setBeatsPerBar =
      _lib.lookupFunction<_SetBeatsPerBarNative, _SetBeatsPerBarDart>(
          'set_beats_per_bar');
  static final _setUseAccentTick =
      _lib.lookupFunction<_SetUseAccentTickNative, _SetUseAccentTickDart>(
          'set_use_accent_tick');
  static final _setBeatAccentLevel =
      _lib.lookupFunction<_SetBeatAccentLevelNative, _SetBeatAccentLevelDart>(
          'set_beat_accent_level');

  /// Native 端的回调 controller。被 C++ 端持有，触发时调用 dart 闭包。
  static NativeCallable<_NativeTick>? _tickCallable;

  /// 唯一订阅者。Controller 在 start() 时订阅，stop()/dispose() 时取消。
  static final StreamController<int> _tickStreamController =
      StreamController<int>.broadcast();

  /// 暴露给业务层的拍点流。每次 C++ 推一帧过来就 +1。
  /// 注意：native 传来的 `beatIndex` 是 `beat % beatsPerBar` 已经是 0..beatsPerBar-1。
  /// 但是底层 C++ 在 beat 0..N 累加，每到 beatsPerBar 重新从 0 开始——刚好等价。
  static Stream<int> get tickStream => _tickStreamController.stream;

  /// 初始化 Oboe 音频流。多次调用只生效一次。
  /// [bpm] 初始 bpm。
  static void init(double bpm) {
    if (_tickCallable != null) return;
    _initAudio(bpm);
    // 把 Dart 函数包成 native 可调用的 callable
    _tickCallable = NativeCallable<_NativeTick>.listener(_onNativeTick);
    _lib.lookupFunction<_SetTickCallbackNative, _SetTickCallbackDart>(
            'set_tick_callback')(
        _tickCallable!.nativeFunction);
  }

  /// C++ 回调入口。运行在 C++ 音频线程。
  /// 通过 StreamController.add 推给 Dart 订阅者，Flutter 会在 UI isolate
  /// 把消息派发出去。
  static void _onNativeTick(int beatIndex) {
    if (_tickStreamController.isClosed) return;
    _tickStreamController.add(beatIndex);
  }

  static void play() => _play();
  static void pause() => _pause();
  static void shutdown() {
    if (_tickCallable == null) return;
    _shutdownAudio();
    _tickCallable!.close();
    _tickCallable = null;
  }

  static void setBpm(double bpm) => _setBpm(bpm);
  static void setBeatsPerBar(int beats) => _setBeatsPerBar(beats);
  static void setUseAccentTick(bool value) => _setUseAccentTick(value);

  /// 设置某拍的重音级别（0=弱, 1=次强, 2=强）。让强弱次强的音色差别真的听得出来。
  /// [beatIndex] 取值 0..beatsPerBar-1。
  static void setBeatAccentLevel(int beatIndex, int level) =>
      _setBeatAccentLevel(beatIndex, level);

  /// 关闭 tick stream（dispose 时调）。
  static Future<void> dispose() async {
    if (!_tickStreamController.isClosed) {
      await _tickStreamController.close();
    }
  }
}
