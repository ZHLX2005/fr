// lib/services/metronome/metronome_service_web.dart
//
// Web stub —— 提供与 native 实现相同的 [MetronomeService] API，但所有调用均为
// 安全 no-op（web 端没有 libmetronome.so，也无法加载本地 WAV）。
//
// 用途：让 main.dart / LabClockProvider / beat_coordinator 等无条件 import
// metronome_service.dart 的代码可以在 web 平台编译通过；行为层面节拍器
// 在 web 上不响（与 native 行为有差距，但不会崩溃）。

import 'dart:async';

/// Web 占位的节拍器服务。
///
/// 仅暴露同名 API；所有方法均 no-op，[tickStream] 为空广播流。
class MetronomeService {
  MetronomeService._();

  static final MetronomeService instance = MetronomeService._();

  final StreamController<int> _tickStreamController =
      StreamController<int>.broadcast();

  /// 拍点流（web 上永不发数据）。
  Stream<int> get tickStream => _tickStreamController.stream;

  /// 初始化 Oboe 音频流。多次调用只生效一次。
  /// Web 端无原生引擎，直接 no-op。
  void ensureReady({double bpm = 120.0}) {}

  /// 设置 BPM —— web 端 no-op。
  void setBpm(double bpm) {}

  /// 设置每小节拍数 —— web 端 no-op。
  void setBeatsPerBar(int beats) {}

  /// 设置某拍的重音级别 —— web 端 no-op。
  void setBeatAccentLevel(int beatIndex, int level) {}

  /// 开始播放 —— web 端 no-op。
  void play() {}

  /// 暂停 —— web 端 no-op。
  void pause() {}

  /// 把 WAV 挂载到指定 accent 档位 —— web 端无文件系统，返回 false。
  bool loadSample(int level, String path) => false;

  /// 卸载指定档位的 WAV —— web 端 no-op。
  void clearSample(int level) {}

  /// 关闭 Oboe 流 —— web 端无资源，直接关闭 controller。
  Future<void> shutdown() async {
    if (!_tickStreamController.isClosed) {
      await _tickStreamController.close();
    }
  }

  /// 测试钩子：reset 全部状态。
  Future<void> resetForTest() => shutdown();
}
