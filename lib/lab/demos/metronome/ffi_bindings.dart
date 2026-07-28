import 'dart:async';

import 'package:xiaodouzi_fr/services/metronome/metronome_service.dart';

/// MetronomeFFI 已被 [MetronomeService] 取代。这个文件保留作为**瘦壳**，
/// 把所有静态方法转发到单例 `MetronomeService.instance`，避免大规模改 consumer
/// 代码（BeatCoordinator、MetronomeController 等）。
///
/// 整个 app 生命周期内**只有一个 Oboe stream 实例**，由 [MetronomeService]
/// 持有。stream / sample 槽都跟随 app 进程，不随 UI 控制器销毁。
///
/// 新代码直接用 `MetronomeService.instance`；旧代码继续通过 `MetronomeFFI.xxx`
/// 也能跑（背后是同一个 service）。
class MetronomeFFI {
  MetronomeFFI._();

  static MetronomeService get _svc => MetronomeService.instance;

  /// Native 端拍点流 — 由 [MetronomeService] 持有，跨 controller 共享。
  static Stream<int> get tickStream => _svc.tickStream;

  /// 初始化 Oboe 音频流。多次调用只生效一次（_initialized flag）。
  static void init(double bpm) => _svc.ensureReady(bpm: bpm);

  static void setBpm(double bpm) => _svc.setBpm(bpm);
  static void setBeatsPerBar(int beats) => _svc.setBeatsPerBar(beats);
  static void setBeatAccentLevel(int beatIndex, int level) =>
      _svc.setBeatAccentLevel(beatIndex, level);

  static void play() => _svc.play();
  static void pause() => _svc.pause();

  /// 一般不调用 — stream 是单例、跟随 app 进程。
  static Future<void> shutdown() => _svc.shutdown();

  static bool loadSample(int level, String path) =>
      _svc.loadSample(level, path);
  static void clearSample(int level) => _svc.clearSample(level);
}