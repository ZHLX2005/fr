import 'dart:async';

/// 拍点调度器接口
///
/// 把"什么时候拍一下"从音频引擎里抽出来，让视图同步和音频播放都用同一个事件源。
abstract class ITickScheduler {
  bool get isRunning;
  int get currentBeatIndex;
  Stream<int> get tickStream;
  void start();
  void stop();
  void setBpm(int bpm);
  void setBeatsPerMeasure(int beats);
  void dispose();
}

/// 用 Timer.periodic 推拍点的实现
///
/// 关键约束：
/// 1. 周期用微秒（Duration(microseconds: ...)），不用整毫秒 —— ms 取整每拍会累
///    积 +1ms，bpm=120 跑 1 分钟就偏移半拍。
/// 2. start/setBpm(运行时)/setBeatsPerMeasure(运行时) 都重启 Timer 且 index 归 0
///    —— 拍号变化后第一拍必须是 index=0，不能让旧 phase 残留。
/// 3. Timer 回调里先 `_currentBeatIndex + 1` 再 emit，避免发射 0 哨兵。
class PeriodicTickScheduler implements ITickScheduler {
  PeriodicTickScheduler({
    int initialBpm = 120,
    int initialBeatsPerMeasure = 4,
  })  : _bpm = initialBpm,
        _beatsPerMeasure = initialBeatsPerMeasure;

  int _bpm;
  int _beatsPerMeasure;
  int _currentBeatIndex = 0;
  bool _isRunning = false;
  Timer? _timer;
  bool _disposed = false;

  final StreamController<int> _controller = StreamController<int>.broadcast();

  @override
  bool get isRunning => _isRunning;

  @override
  int get currentBeatIndex => _currentBeatIndex;

  @override
  Stream<int> get tickStream => _controller.stream;

  @override
  void start() {
    if (_disposed || _isRunning) return;
    _isRunning = true;
    _currentBeatIndex = 0;
    _scheduleTimer();
  }

  @override
  void stop() {
    if (!_isRunning) return;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  @override
  void setBpm(int bpm) {
    _bpm = bpm;
    if (_isRunning) {
      _timer?.cancel();
      _currentBeatIndex = 0;
      _scheduleTimer();
    }
  }

  @override
  void setBeatsPerMeasure(int beats) {
    _beatsPerMeasure = beats;
    if (_isRunning) {
      _timer?.cancel();
      _currentBeatIndex = 0;
      _scheduleTimer();
    }
  }

  void _scheduleTimer() {
    if (_disposed) return;
    // 微秒级周期，避免 ms 取整漂移
    final periodMicros = 60000000 ~/ _bpm;
    _timer = Timer.periodic(
      Duration(microseconds: periodMicros),
      (_) {
        if (_disposed || !_isRunning) return;
        _currentBeatIndex = (_currentBeatIndex + 1) % _beatsPerMeasure;
        if (!_controller.isClosed) {
          _controller.add(_currentBeatIndex);
        }
      },
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}
