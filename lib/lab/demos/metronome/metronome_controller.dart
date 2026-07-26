import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'beat_buffer_generator.dart';
import 'const_metronome.dart';

/// 节拍器控制器
///
/// 这里避了三个坑，改的时候都不要动：
///
/// 1. **播放/停止串行化**。旧代码的 `togglePlay` 是异步的，第一次点击后 `_isPlaying`
///    要过 4 个 `await` 才被置位，其间的第二次点击会走进另一个 `start()`，一起写
///    临时文件、一起 `setFilePath`，`just_audio` 端只会认最后一个 —— 表现就是
///    "按钮要按两次、按钮失灵"。修法：一进来先同步翻 `_isPlaying`（意图立即生效），
///    真正的音频操作全部丢进 [_queue]，一个跑完再跑下一个。
///
/// 2. **节拍指示走音频时钟**。旧代码用 `Timer.periodic((60000/bpm).round() ms)`
///    独立于音频推拍点，两条时钟以毫秒为单位取整，几秒后就能看出偏移 ——
///    这就是"音画偏移"。修法：订阅 [AudioPlayer.createPositionStream]，从
///    实际播放位置反推当前拍号，播多快指示器就跟多快。
///
/// 3. **BPM 改动防抖**。Slider onChanged 每帧触发，旧代码每帧都会重生成 WAV +
///    写盘 + setFilePath —— 拖动时磁盘和解码器都被打爆，其它按钮点了没响应就是
///    被这条阻塞了。修法：BPM/拍号变化只安排一个 [_reloadDebounce] 定时器，
///    停手 [MetronomeDefaults.reloadDebounceMs] 毫秒才真正重载。
class MetronomeController extends ChangeNotifier {
  MetronomeController({AudioPlayer? audioPlayer})
      : _audioPlayer = audioPlayer ?? AudioPlayer() {
    _initFuture = _initPlayer();
  }

  // ==================== 状态 ====================

  int _bpm = MetronomeDefaults.defaultBpm;
  int get bpm => _bpm;

  BeatPattern _beatPattern = MetronomePresets.defaultPattern;
  BeatPattern get beatPattern => _beatPattern;

  /// 用户意图上"是否在播放"。这里是意图，不是音频引擎的实时状态 —— 点了 play
  /// 之后音频要过几十毫秒才真正出声，这段时间 [_isPlaying] 已经是 true，UI 也
  /// 该表现成"正在播放"，否则用户以为按钮没响应又戳一下。
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// 当前小节内的拍序号（0 起）。由 [_audioPlayer.positionStream] 推出来，不是
  /// 独立时钟。UI 用 [ValueListenableBuilder] 监听它，避免整页 rebuild。
  final ValueNotifier<int> currentBeatNotifier = ValueNotifier(0);
  int get currentBeatIndex => currentBeatNotifier.value;

  /// 音频初始化/重载失败时的错误消息，UI 侧监听后弹 SnackBar。旧代码在
  /// catch 里 debugPrint 就算完了 —— 播不出声用户看不到任何提示。
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  // ==================== 音频引擎 ====================

  final AudioPlayer _audioPlayer;
  late final Future<void> _initFuture;

  /// 复用同一份临时文件路径，不像旧代码每次 start 都用时间戳生成新文件 ——
  /// 用户拖 slider 一分钟能攒下几百个 wav。
  String? _tempWavPath;

  /// 位置流订阅。重载时先取消再订新的，否则会有旧订阅继续把过期的拍号写进
  /// [currentBeatNotifier]。
  StreamSubscription<Duration>? _positionSub;

  // ==================== 串行化 & 防抖 ====================

  /// 音频操作 FIFO 队列。所有会触碰 [_audioPlayer] 的动作都要挂到它后面，
  /// 保证同一时刻只有一个在 setFilePath/play/stop。
  Future<void> _queue = Future.value();

  /// BPM/拍号变化的重载防抖。Slider 拖动时每帧都会调 [setBpm]，没有它
  /// 每帧都要重写 WAV。
  Timer? _reloadDebounce;

  // ==================== Tap Tempo ====================

  final List<DateTime> _tapTimes = [];

  // ==================== 生命周期 ====================

  Future<void> _initPlayer() async {
    await _audioPlayer.setLoopMode(LoopMode.all);
    await _audioPlayer.setVolume(1.0);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _positionSub?.cancel();
    _audioPlayer.dispose();
    currentBeatNotifier.dispose();
    errorNotifier.dispose();
    if (_tempWavPath != null) {
      final f = File(_tempWavPath!);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {
          // 删失败也无所谓，OS 会清理临时目录
        }
      }
    }
    super.dispose();
  }

  // ==================== 对外操作 ====================

  void setBpm(int newBpm) {
    final clamped =
        newBpm.clamp(MetronomeDefaults.minBpm, MetronomeDefaults.maxBpm);
    if (_bpm == clamped) return;
    _bpm = clamped;
    notifyListeners();
    if (_isPlaying) _scheduleReload();
  }

  void incrementBpm() => setBpm(_bpm + 1);
  void decrementBpm() => setBpm(_bpm - 1);

  void setBeatPattern(BeatPattern pattern) {
    if (_beatPattern == pattern) return;
    _beatPattern = pattern;
    // 拍号变了，当前拍号可能超出新小节 —— 先归零，等 positionStream 追上来
    currentBeatNotifier.value = 0;
    notifyListeners();
    if (_isPlaying) _scheduleReload();
  }

  Future<void> togglePlay() => _isPlaying ? stop() : start();

  Future<void> start() {
    if (_isPlaying) return Future.value();
    _isPlaying = true;
    notifyListeners();
    return _enqueue(_loadAndPlay);
  }

  Future<void> stop() {
    if (!_isPlaying) return Future.value();
    _isPlaying = false;
    currentBeatNotifier.value = 0;
    notifyListeners();
    return _enqueue(() async {
      _positionSub?.cancel();
      _positionSub = null;
      await _audioPlayer.stop();
    });
  }

  Future<void> pause() {
    if (!_isPlaying) return Future.value();
    _isPlaying = false;
    notifyListeners();
    return _enqueue(() async {
      _positionSub?.cancel();
      _positionSub = null;
      await _audioPlayer.pause();
    });
  }

  /// Tap Tempo - 记录点击
  void tap() {
    final now = DateTime.now();

    // 隔太久（上一段完全过时了）就重开
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
    // 抖动太厉害就不采信（比如误触）
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

  // ==================== 内部实现 ====================

  /// 把 [action] 串到队列末尾。整段包在 try/catch 里 —— 队列本身不能因为
  /// 一次操作抛异常就断掉，否则后续所有 play/stop 都会卡住。
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) async {
      try {
        await action();
      } catch (e, st) {
        debugPrint('Metronome audio op failed: $e\n$st');
        errorNotifier.value = e.toString();
      }
    });
    _queue = next;
    return next;
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(
      const Duration(milliseconds: MetronomeDefaults.reloadDebounceMs),
      () {
        // 定时器触发时用户可能已经停了 —— 交给队列的最新状态判断
        if (_isPlaying) _enqueue(_loadAndPlay);
      },
    );
  }

  Future<void> _loadAndPlay() async {
    await _initFuture;
    // 用户在等待间已经又按了停止，就别播了
    if (!_isPlaying) return;

    final loop = BeatBufferGenerator.generateLoop(
      bpm: _bpm,
      beatPattern: _beatPattern,
    );

    _tempWavPath ??=
        '${(await getTemporaryDirectory()).path}/metronome_loop.wav';
    await File(_tempWavPath!).writeAsBytes(loop.wav);

    // setFilePath 会重置 position 到 0，正好对应"下一轮从第 1 拍开始"
    await _audioPlayer.setFilePath(_tempWavPath!);

    // 再确认一次意图 —— setFilePath 期间用户可能已经停了
    if (!_isPlaying) return;

    await _audioPlayer.play();
    _subscribePosition(loop);
  }

  /// 从音频实际位置反推当前拍号。这里 [AudioPlayer.createPositionStream] 的更新
  /// 频率被拉到 ~60fps，才够精细驱动节拍点闪烁；默认的 200ms 会漏掉快 bpm 的
  /// 拍点切换（bpm=200 一拍才 300ms）。
  void _subscribePosition(BeatLoop loop) {
    _positionSub?.cancel();
    final beatMicros = loop.beatDuration.inMicroseconds;
    final beatsPerMeasure = _beatPattern.beatsPerMeasure;
    if (beatMicros == 0 || beatsPerMeasure == 0) return;

    _positionSub = _audioPlayer
        .createPositionStream(
      minPeriod: const Duration(milliseconds: 16),
      maxPeriod: const Duration(milliseconds: 16),
    )
        .listen((pos) {
      if (!_isPlaying) return;
      final idx = (pos.inMicroseconds ~/ beatMicros) % beatsPerMeasure;
      if (currentBeatNotifier.value != idx) {
        currentBeatNotifier.value = idx;
      }
    });
  }
}
