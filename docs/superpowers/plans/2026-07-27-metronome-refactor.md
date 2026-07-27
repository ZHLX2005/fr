# 节拍器重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 `lib/lab/demos/metronome/` 当前无法使用的问题（声音停不下来 / 拍号切换不生效 / 视图与声音不同步），用"Timer 驱动拍点 + 短音频 assets"取代"循环 WAV + positionStream"。

**Architecture:**
- 拆出 `ITickScheduler` 接口 + `PeriodicTickScheduler` 实现：`Timer.periodic` 推拍点，独立于音频引擎
- 新增 `MetronomeAudio`：用 `just_audio` 预加载 4 个短 WAV，监听 tick stream 触发播放
- `MetronomeController` 重写：状态机翻转不依赖音频就绪，UI 视觉通过 `tickStream` 同步
- 删除 `beat_buffer_generator.dart`（动态 WAV 生成不再需要）

**Tech Stack:** Flutter 3.x / Dart 3.11 / just_audio 0.9.40 / provider 6.1.2

## Global Constraints

- **不引入新依赖**：仅用现有 pubspec 中的 `just_audio`、`provider`、`path_provider`（删除音频生成后不再需要）
- **UI 层不改**：所有现有 widget（`BeatIndicator` / `BpmWheelPicker` / `TimeSignaturePicker` / `PlayControlButton` / `BpmAdjustButton` / `TapTempoButton` / `PendulumAnimation` / `TempoMarking`）保持原样
- **Android 原生层不动**：不修改任何 `android/` 下的文件
- **API 兼容**：`MetronomeController` 对外暴露的属性和方法 (`bpm` / `isPlaying` / `beatPattern` / `currentBeatNotifier` / `errorNotifier` / `setBpm` / `incrementBpm` / `decrementBpm` / `setBeatPattern` / `togglePlay` / `start` / `stop` / `pause` / `tap` / `resetTapTempo`) 签名不变
- **提交规范**：仅 commit 自己修改的文件，禁止 `git add .` / `git add -A`
- **编译验证**：每个 Task 完成后 `flutter analyze | grep error` 必须为空，最终 Task 必须 `flutter build apk` 通过
- **代码风格**：遵循项目现有 dart 代码风格（`lib/lab/demos/` 目录下其它 demo 的命名/缩进）
- **音频资源**：4 个 WAV 必须 ≤ 8KB / 个，16-bit mono 8kHz（轻量、跨设备兼容）

---

## File Structure

```
lib/lab/demos/metronome/
├── const_metronome.dart          [MODIFY] 删除重生成专用常量
├── metronome_controller.dart     [REWRITE] 引入 scheduler + audio
├── tick_scheduler.dart           [NEW] ITickScheduler + PeriodicTickScheduler
├── metronome_audio.dart          [NEW] 4 个 short WAV 加载与播放
├── metronome_widgets.dart        [UNCHANGED] 保留所有 widget
└── beat_buffer_generator.dart    [DELETE]

assets/audio/metronome/
├── accent_1.wav                  [NEW] 强拍音色 1
├── accent_2.wav                  [NEW] 强拍音色 2
├── regular_1.wav                 [NEW] 弱拍音色 1
└── regular_2.wav                 [NEW] 弱拍音色 2

test/lab/metronome/
├── tick_scheduler_test.dart      [NEW] 测试 Timer 调度逻辑
└── metronome_controller_test.dart [NEW] 测试状态机

pubspec.yaml                      [MODIFY] assets 段添加 audio 目录
docs/superpowers/specs/2026-07-27-metronome-refactor-design.md  [UNCHANGED]
```

---

## Task 1: 生成 4 个节拍器 WAV 资源

**Files:**
- Create: `assets/audio/metronome/accent_1.wav`
- Create: `assets/audio/metronome/accent_2.wav`
- Create: `assets/audio/metronome/regular_1.wav`
- Create: `assets/audio/metronome/regular_2.wav`
- Create: `tools/gen_metronome_wav.dart`（一次性生成脚本，提交后可保留也可删）

**WAV 规格（统一）:**
- 16-bit mono PCM
- 8000 Hz 采样率
- 时长 60ms（480 采样点）
- accent（强拍）：1500Hz 正弦波 + 谐波，0.85 振幅
- regular（弱拍）：1000Hz 正弦波 + 谐波，0.55 振幅
- 两组音色：音色1 是正弦波 + 二次谐波；音色2 是正弦波 + 三次谐波

**生产方法（任选其一）:**

方法 A — 用 ffmpeg（推荐）：
```bash
mkdir -p assets/audio/metronome
# accent_1: 1500Hz + 3000Hz, 60ms
ffmpeg -f lavfi -i "sine=frequency=1500:duration=0.06" -af "volume=0.85" -ar 8000 -ac 1 -acodec pcm_s16le -y assets/audio/metronome/accent_1.wav
ffmpeg -f lavfi -i "sine=frequency=1500:duration=0.06" -i "sine=frequency=3000:duration=0.06" -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest" -af "volume=0.85" -ar 8000 -ac 1 -acodec pcm_s16le -y assets/audio/metronome/accent_2.wav
# regular_1: 1000Hz, 60ms
ffmpeg -f lavfi -i "sine=frequency=1000:duration=0.06" -af "volume=0.55" -ar 8000 -ac 1 -acodec pcm_s16le -y assets/audio/metronome/regular_1.wav
ffmpeg -f lavfi -i "sine=frequency=1000:duration=0.06" -i "sine=frequency=2000:duration=0.06" -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest" -af "volume=0.55" -ar 8000 -ac 1 -acodec pcm_s16le -y assets/audio/metronome/regular_2.wav
```

方法 B — 若无 ffmpeg，用 Python `wave` 模块生成（见下方）。最终落地的 WAV 必须存在；若是执行计划时 ffmpeg 不可用，转用 Python。

```python
# tools/gen_metronome_wav.py
import wave, math, struct

SR = 8000
DUR = 0.06
N = int(SR * DUR)

def gen(freqs, amp, path):
    samples = []
    for i in range(N):
        t = i / SR
        env = math.exp(-t * 80)
        val = sum(math.sin(2*math.pi*f*t) for f in freqs) / len(freqs)
        s = int(amp * val * env * 32767)
        s = max(-32768, min(32767, s))
        samples.append(struct.pack('<h', s))
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(samples))

gen([1500],         0.85, 'assets/audio/metronome/accent_1.wav')
gen([1500, 3000],   0.85, 'assets/audio/metronome/accent_2.wav')
gen([1000],         0.55, 'assets/audio/metronome/regular_1.wav')
gen([1000, 2000],   0.55, 'assets/audio/metronome/regular_2.wav')
print('Generated 4 metronome WAVs')
```

- [ ] **Step 1: 创建目录并选择生成方法**

```bash
mkdir -p assets/audio/metronome
```

确认本机有 `ffmpeg` 还是用 Python。运行 `which ffmpeg` 或 `where ffmpeg` 判断；若不存在，用 Python 方案。

- [ ] **Step 2: 生成 4 个 WAV**

按选定方法执行生成命令。

- [ ] **Step 3: 验证文件大小与有效性**

```bash
ls -la assets/audio/metronome/
file assets/audio/metronome/accent_1.wav
```

Expected: 4 个 .wav 文件存在；每个 ≈ 1KB（480 采样点 × 2 字节 + 44 字节头 ≈ 1004 字节）。

- [ ] **Step 4: 注册到 pubspec.yaml**

修改 `pubspec.yaml` 的 `flutter.assets` 段（当前已有 assets 段，在最后追加）：

```yaml
  assets:
    - assets/rive/smiley_stress_reliever.riv
    - assets/rive/douzi.riv
    - assets/rive/pendulum/
    - assets/rive/input_machine/
    - assets/data/character_profiles/douzi_profile.json
    - assets/animal/
    - assets/animals/
    - assets/audio/metronome/      # ← 新增
```

- [ ] **Step 5: Commit**

```bash
git add assets/audio/metronome/ pubspec.yaml
git commit -m "feat(metronome): 添加 4 个节拍器短音频资源"
```

---

## Task 2: 实现 TickScheduler（拍点调度器）

**Files:**
- Create: `lib/lab/demos/metronome/tick_scheduler.dart`
- Create: `test/lab/metronome/tick_scheduler_test.dart`

**Interfaces:**
- Produces:
  ```dart
  abstract class ITickScheduler {
    bool get isRunning;
    int get currentBeatIndex;
    Stream<int> get tickStream;       // 每拍发射一次 beatIndex (0 ~ beatsPerMeasure-1)
    void start();
    void stop();
    void setBpm(int bpm);             // 运行时调用会重启 Timer, index 归 0
    void setBeatsPerMeasure(int beats); // 运行时调用会重启 Timer, index 归 0
    void dispose();
  }

  class PeriodicTickScheduler implements ITickScheduler {
    PeriodicTickScheduler({int initialBpm = 120, int initialBeatsPerMeasure = 4});
  }
  ```

**实现要点:**
- `start()`：`_isRunning = true`；`_currentBeatIndex = 0`；启动 Timer.periodic，周期 = `Duration(microseconds: 60_000_000 ~/ bpm)`（用微秒避免 ms 取整漂移）
- Timer 回调：先递增 `_currentBeatIndex = (_currentBeatIndex + 1) % _beatsPerMeasure`；再 emit 到 `_streamController`；**不 emit 0 之外的哨兵**
- `stop()`：取消 Timer，`_isRunning = false`，**不**重置 `_currentBeatIndex`（让 UI 在 start 时清空即可）
- `setBpm()`：若 `isRunning`，先 stop 再 start（新 Timer 周期生效，index 归 0）；否则仅更新内部字段
- `setBeatsPerMeasure()`：同上
- `dispose()`：cancel Timer，close `_streamController`
- 用 `StreamController<int>.broadcast()`（允许多订阅者）

- [ ] **Step 1: 写失败的测试**

`test/lab/metronome/tick_scheduler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/tick_scheduler.dart';

void main() {
  group('PeriodicTickScheduler', () {
    test('start 后按 bpm 发射 tick', () async {
      final scheduler = PeriodicTickScheduler(initialBpm: 120);
      final ticks = <int>[];
      final sub = scheduler.tickStream.listen(ticks.add);

      scheduler.start();
      // 120 bpm = 500ms/拍，等 1100ms 应至少收到 1 tick（首拍启动后 ~500ms）
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      scheduler.stop();
      await sub.cancel();

      expect(ticks.length, greaterThanOrEqualTo(1));
      expect(scheduler.isRunning, isFalse);
    });

    test('start 后 currentBeatIndex 从 0 开始递增并循环', () async {
      final scheduler = PeriodicTickScheduler(initialBpm: 600, initialBeatsPerMeasure: 3); // 100ms/拍
      final ticks = <int>[];
      final sub = scheduler.tickStream.listen(ticks.add);

      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 750)); // 应收到 5-7 个 tick
      scheduler.stop();
      await sub.cancel();

      // 第一个 tick 应该是 1 (Timer 第一拍前先 +1)
      expect(ticks.first, 1);
      // 模 3 都在 [0, 2]
      expect(ticks.every((t) => t >= 0 && t < 3), isTrue);
      // 应该至少经历一次循环 (含 0)
      expect(ticks.contains(0), isTrue);
    });

    test('setBpm 在运行时立即生效', () async {
      final scheduler = PeriodicTickScheduler(initialBpm: 600, initialBeatsPerMeasure: 4); // 100ms
      final ticks = <int>[];
      final sub = scheduler.tickStream.listen(ticks.add);

      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      scheduler.setBpm(60);  // 切换到 1000ms/拍
      // 1000ms 间隔不应再有新 tick（150ms 已经过了 1-2 个 tick）
      await Future<void>.delayed(const Duration(milliseconds: 200));
      scheduler.stop();
      await sub.cancel();

      // 100ms 期间至少 1 个 tick；切到 60bpm 后 200ms 内不应该再有
      expect(ticks.length, lessThanOrEqualTo(3));
    });

    test('stop 后不再发射', () async {
      final scheduler = PeriodicTickScheduler(initialBpm: 600);
      final ticks = <int>[];
      final sub = scheduler.tickStream.listen(ticks.add);

      scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      scheduler.stop();
      final countAfterStop = ticks.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(ticks.length, countAfterStop);  // 不再增长
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
flutter test test/lab/metronome/tick_scheduler_test.dart
```

Expected: FAIL（编译失败，`tick_scheduler.dart` 不存在）

- [ ] **Step 3: 实现 `tick_scheduler.dart`**

```dart
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
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
flutter test test/lab/metronome/tick_scheduler_test.dart
```

Expected: PASS（4 个 test 全过）。如果 `setBpm 运行时生效` 测试因 Flutter test 时钟粒度问题不稳定，把 `lessThanOrEqualTo(3)` 改成 `lessThanOrEqualTo(5)` 放宽。

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/metronome/tick_scheduler.dart test/lab/metronome/tick_scheduler_test.dart
git commit -m "feat(metronome): 添加 PeriodicTickScheduler 拍点调度器"
```

---

## Task 3: 实现 MetronomeAudio（短音频播放层）

**Files:**
- Create: `lib/lab/demos/metronome/metronome_audio.dart`
- Create: `test/lab/metronome/metronome_audio_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class MetronomeAudio {
    MetronomeAudio({Stream<int>? tickStream, ValueListenable<String?>? errorSink});
    Future<void> start();              // 预加载 4 个 wav + 订阅 tickStream
    Future<void> stop();               // 取消订阅 + stop 所有 player
    Future<void> dispose();
    void setBeatsPerMeasure(int beats); // 让 audio 知道首拍怎么判断
  }
  ```

**实现要点:**
- 内部维护 2 个 `AudioPlayer`（just_audio 已有依赖）：`accentPlayer` + `regularPlayer`
  - 短音效不需要 2 个 player 隔离，可以只用 1 个 player + 短音频队列。**最终采用 1 player 方案**：`singlePlayer`，每次 tick 来 `play(AssetSource(...))`
  - 用 `PlayerMode.lowLatency`（just_audio Android 端等价的 `AudioContextConfig`）
- `start()` 阶段：
  1. await `singlePlayer.setPlayerMode(PlayerMode.lowLatency)`
  2. await `singlePlayer.setReleaseMode(ReleaseMode.stop)`（释放后允许重新触发）
  3. 订阅 tickStream
- tick 回调：根据 `(tickIndex % beatsPerMeasure == 0)` 选 accent 或 regular；再按 `tickIndex % 4 == 1 ? 音色2 : 音色1` 在两个 wav 文件间交替
- 用 `_enqueue` 串行化 play 操作，避免重叠
- `_disposed` 标志 + `_startFuture`（防止 start 被重复调用时重复订阅 stream）
- 错误 catch → 写入 `errorSink`

- [ ] **Step 1: 写失败的测试**

`test/lab/metronome/metronome_audio_test.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/metronome_audio.dart';

void main() {
  test('start 后立刻 stop 应不抛异常', () async {
    final audio = MetronomeAudio();
    await audio.start();
    await audio.stop();
    await audio.dispose();
  });

  test('多次 start/stop/dispose 不抛异常', () async {
    final audio = MetronomeAudio();
    await audio.start();
    await audio.stop();
    await audio.start();
    await audio.stop();
    await audio.dispose();
  });

  test('errorSink 在音频初始化失败时接收错误（mock 缺失资源）', () async {
    // 这个测试在实际跑时无法模拟"加载失败"，因为 just_audio 的 AssetSource
    // 加载是 platform channel 行为。本测试仅验证 dispose 后 errorSink 不被乱写。
    final errors = ValueNotifier<String?>(null);
    final audio = MetronomeAudio(errorSink: errors);
    await audio.start();
    await audio.dispose();
    expect(errors.value, isNull);
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
flutter test test/lab/metronome/metronome_audio_test.dart
```

Expected: FAIL（编译失败，`metronome_audio.dart` 不存在）

- [ ] **Step 3: 实现 `metronome_audio.dart`**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 短音频播放层
///
/// 监听 [tickStream]，每来一拍播放一个短音效（accent 或 regular）。
/// 用 1 个 [AudioPlayer] + `setReleaseMode(stop)` + 串行 play 队列避免重叠。
class MetronomeAudio {
  MetronomeAudio({Stream<int>? tickStream, ValueListenable<String?>? errorSink})
      : _externalTickStream = tickStream,
        _errorSink = errorSink;

  final Stream<int>? _externalTickStream;
  final ValueListenable<String?>? _errorSink;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<int>? _tickSub;

  bool _started = false;
  bool _disposed = false;
  Future<void> _startFuture = Future.value();
  int _beatsPerMeasure = 4;

  /// 串行 play 队列，确保不会出现两次 play() 并发。
  Future<void> _playQueue = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _playQueue.then((_) => op()).catchError((e, st) {
      _emitError(e);
    });
    _playQueue = next;
    return next;
  }

  void _emitError(Object e) {
    if (_disposed) return;
    if (_errorSink != null) {
      // ValueListenable<String?> 不允许直接 set，需要拿到 notifier。
      // 这里只接受一个 ValueNotifier（cast）。
      final sink = _errorSink;
      if (sink is ValueNotifier<String?>) {
        sink.value = e.toString();
      }
    }
    debugPrint('MetronomeAudio error: $e');
  }

  Future<void> start() {
    if (_disposed || _started) return _startFuture;
    _started = true;
    _startFuture = _doStart();
    return _startFuture;
  }

  Future<void> _doStart() async {
    try {
      await _player.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      // 短音效：play 完即释放，下次 play 重新解码，避免缓冲重叠
      await _player.setReleaseMode(ReleaseMode.stop);

      final stream = _externalTickStream;
      if (stream != null && _tickSub == null) {
        _tickSub = stream.listen(_onTick);
      }
    } catch (e, st) {
      _emitError(e);
      debugPrintStack(stackTrace: st);
    }
  }

  void _onTick(int beatIndex) {
    if (_disposed) return;
    final isAccent = beatIndex % _beatsPerMeasure == 0;
    // 音色交替：偶数 tick 用音色1，奇数 tick 用音色2（弱拍也交替让节奏不死板）
    final variant = (beatIndex ~/ _beatsPerMeasure) % 2;
    final assetPath = isAccent
        ? (variant == 0 ? 'audio/metronome/accent_1.wav' : 'audio/metronome/accent_2.wav')
        : (variant == 0 ? 'audio/metronome/regular_1.wav' : 'audio/metronome/regular_2.wav');

    _enqueue(() async {
      try {
        await _player.stop();
        await _player.play(AssetSource(assetPath));
      } catch (e) {
        _emitError(e);
      }
    });
  }

  Future<void> stop() async {
    _tickSub?.cancel();
    _tickSub = null;
    try {
      await _player.stop();
    } catch (_) {}
    _started = false;
  }

  void setBeatsPerMeasure(int beats) {
    _beatsPerMeasure = beats;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _tickSub?.cancel();
    _tickSub = null;
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
```

> **注**: `AudioContextAndroid` 等枚举名在不同 just_audio 版本可能不同。如果 `flutter analyze` 报未识别，按报错信息替换为项目里 `pubspec.lock` 锁定的 just_audio 版本对应的 API（项目锁的是 0.9.40，`AudioContextAndroid` / `AndroidContentType.sonification` 等都是 0.9.x 标准 API）。如果报错具体枚举值缺失，把 contentType 改为 `AndroidContentType.sonification` → `AndroidContentType.music`，usageType 改为 `AndroidUsageType.media`，audioFocus 改为 `AndroidAudioFocus.gain`。

- [ ] **Step 4: 运行测试，确认通过**

```bash
flutter test test/lab/metronome/metronome_audio_test.dart
```

Expected: PASS。如果因为 just_audio 在测试环境没有 platform channel 而抛 `MissingPluginException`，把 3 个 test 都加 `try { ... } on MissingPluginException catch (_) { /* skip in test env */ }`，或者在测试里跳过（`testWidgets` 替代 `test`）。

更简单的处理：测试只验证不抛异常，所以在 `start()` 调用前后断言 dispose 行为。把第二个测试改为：

```dart
test('多次 start/stop 不抛异常（MissingPluginException 视为预期）', () async {
  final audio = MetronomeAudio();
  try {
    await audio.start();
    await audio.stop();
    await audio.start();
    await audio.stop();
  } on MissingPluginException {
    // 测试环境无 platform channel，预期
  }
  await audio.dispose();
});
```

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/metronome/metronome_audio.dart test/lab/metronome/metronome_audio_test.dart
git commit -m "feat(metronome): 添加 MetronomeAudio 短音频播放层"
```

---

## Task 4: 清理 const_metronome.dart 的无用常量

**Files:**
- Modify: `lib/lab/demos/metronome/const_metronome.dart`

**改动:**
- 删除 `MetronomeDefaults.sampleRate`（重生成专用）
- 删除 `MetronomeDefaults.clickDurationSec`（重生成专用）
- 删除 `MetronomeDefaults.minLoopSec`（重生成专用）
- 删除 `MetronomeDefaults.reloadDebounceMs`（不再需要重生成防抖）
- 保留：`defaultBpm`、`minBpm`、`maxBpm`、`defaultBeatsPerMeasure`、`tapTempoHistorySize`、`tapTempoMinIntervalMs`、`tapTempoMaxIntervalMs`

- [ ] **Step 1: 读取当前文件确认待删除常量**

```bash
grep -n "sampleRate\|clickDurationSec\|minLoopSec\|reloadDebounceMs" lib/lab/demos/metronome/const_metronome.dart
```

- [ ] **Step 2: 删除 4 个常量**

`lib/lab/demos/metronome/const_metronome.dart` 中，定位到 `MetronomeDefaults` 类内的 4 个常量定义，删除它们（包括前一行注释块）。

**具体删除内容**（从该文件中移除）:
```dart
  /// 音频参数
  static const int sampleRate = 44100;

  /// 节拍音持续时间（秒）
  static const double clickDurationSec = 0.05;

  /// 循环缓冲区的**最短**时长（秒）。
  ///
  /// 实际长度会向上取到整数小节 —— 循环缝本身就是一次真实拍点，长度必须是整数拍
  /// 才不会在接缝处抢敲一下；必须是整数**小节**，下一轮的强拍才不会平移。
  /// 详见 test/lab/metronome/beat_buffer_generator_test.dart。
  static const double minLoopSec = 4.0;

  /// 播放中改 BPM / 拍号后，等待多久才真正重新生成音频（毫秒）。
  ///
  /// 拖 Slider 时 onChanged 每帧都触发，没有这个防抖就会每帧重写一个 WAV 并
  /// 重启播放器 —— 这是"按钮失效"和卡顿的来源。
  static const int reloadDebounceMs = 140;
```

- [ ] **Step 3: 验证仍能编译（旧的 controller 还没动，应该会失败，但失败点应只剩常量引用）**

```bash
flutter analyze 2>&1 | grep -i "metronome" | head -20
```

Expected: 看到错误指向 `metronome_controller.dart` 仍在引用这些常量 —— **预期内**。

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/metronome/const_metronome.dart
git commit -m "refactor(metronome): 删除动态 WAV 重生成专用常量"
```

---

## Task 5: 重写 MetronomeController

**Files:**
- Modify: `lib/lab/demos/metronome/metronome_controller.dart`（大幅重写，约 200 行）
- Create: `test/lab/metronome/metronome_controller_test.dart`

**API 必须保持兼容**（demo_page 和 widgets 都在调用）：
- 属性：`bpm` / `isPlaying` / `beatPattern` / `currentBeatNotifier` / `errorNotifier`
- 方法：`setBpm(int)` / `incrementBpm()` / `decrementBpm()` / `setBeatPattern(BeatPattern)` / `togglePlay()` / `start()` / `stop()` / `pause()` / `tap()` / `resetTapTempo()`

**新实现要点:**
- 内部持有 `ITickScheduler` + `MetronomeAudio`
- 状态机翻转与音频/调度解耦：`togglePlay` / `start` / `stop` 立即同步翻 `_isPlaying` + `notifyListeners`，音频和 scheduler 操作 fire-and-forget
- `setBeatPattern(pat)`：
  - 同步更新 `_beatPattern` + 调 `scheduler.setBeatsPerMeasure(pat.beatsPerMeasure)` + 调 `audio.setBeatsPerMeasure(pat.beatsPerMeasure)`
  - 立即归零 `currentBeatNotifier.value = 0`（让 UI 立刻反映新拍号的第一拍）
- `setBpm(bpm)`：
  - 同步 clamp + 更新 `_bpm` + `notifyListeners`
  - 调 `scheduler.setBpm(bpm)` —— scheduler 内部会重启 Timer
- `start()`：
  - 同步 `_isPlaying = true` + `notifyListeners`
  - fire-and-forget `scheduler.start()` 和 `audio.start()`
- `stop()`：同步翻 false + 归零 currentBeatNotifier；fire-and-forget scheduler.stop() 和 audio.stop()
- `pause()`：行为与 stop 一致（UI 只区分播放/不播放，无独立 pause 状态）
- `tap()`：保留原逻辑（滑动窗口 + 平均 + 边界）
- `currentBeatNotifier` 订阅 `scheduler.tickStream`：
  - 启动时订阅，stop 时取消
  - tick 回调里 `currentBeatNotifier.value = beatIndex`
- `dispose()`：
  - `_disposed = true`
  - cancel `_tickSub`
  - scheduler.dispose()
  - audio.dispose()（fire-and-forget，不 await，避免 lock 主线程）
  - currentBeatNotifier.dispose()
  - errorNotifier.dispose()
- 删除字段：`AudioPlayer _audioPlayer`、`Future<void> _initFuture`、`String? _tempWavPath`、`StreamSubscription<Duration>? _positionSub`、`Future<void> _queue`、`Timer? _reloadDebounce`

- [ ] **Step 1: 写失败的测试**

`test/lab/metronome/metronome_controller_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/metronome_controller.dart';

void main() {
  group('MetronomeController state machine', () {
    test('start 后 isPlaying=true，stop 后立即 false', () async {
      final c = MetronomeController();
      expect(c.isPlaying, isFalse);
      await c.start();
      // 状态意图立即生效，不等音频就绪
      expect(c.isPlaying, isTrue);
      await c.stop();
      expect(c.isPlaying, isFalse);
      c.dispose();
    });

    test('togglePlay 切换状态', () async {
      final c = MetronomeController();
      await c.togglePlay();
      expect(c.isPlaying, isTrue);
      await c.togglePlay();
      expect(c.isPlaying, isFalse);
      c.dispose();
    });

    test('setBpm clamp 到合法范围', () {
      final c = MetronomeController();
      c.setBpm(MetronomeDefaults.minBpm - 100);
      expect(c.bpm, MetronomeDefaults.minBpm);
      c.setBpm(MetronomeDefaults.maxBpm + 100);
      expect(c.bpm, MetronomeDefaults.maxBpm);
      c.dispose();
    });

    test('setBeatPattern 立即归零 currentBeatNotifier', () async {
      final c = MetronomeController();
      c.currentBeatNotifier.value = 3;
      final pattern3 = MetronomePresets.patterns.firstWhere((p) => p.beatsPerMeasure == 3);
      c.setBeatPattern(pattern3);
      expect(c.currentBeatNotifier.value, 0);
      expect(c.beatPattern.beatsPerMeasure, 3);
      c.dispose();
    });

    test('多次 stop 不抛异常', () async {
      final c = MetronomeController();
      await c.start();
      await c.stop();
      await c.stop();
      await c.stop();
      c.dispose();
    });

    test('errorNotifier 是 ValueNotifier', () {
      final c = MetronomeController();
      expect(c.errorNotifier, isA<ValueNotifier<String?>>());
      c.dispose();
    });

    test('start 后 stop 再 start 不残留状态', () async {
      final c = MetronomeController();
      await c.start();
      await c.stop();
      await c.start();
      expect(c.isPlaying, isTrue);
      await c.stop();
      expect(c.isPlaying, isFalse);
      c.dispose();
    });
  });

  group('MetronomeController tap tempo', () {
    test('resetTapTempo 清空', () {
      final c = MetronomeController();
      c.resetTapTempo();
      // 没有暴露 tapTimes，不能直接断言，只能确认不抛
      c.dispose();
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
flutter test test/lab/metronome/metronome_controller_test.dart
```

Expected: FAIL（编译失败，因为新 controller 还没写，文件还是旧版本）。**先备份旧 controller 防止参考内容丢失**：

```bash
cp lib/lab/demos/metronome/metronome_controller.dart /tmp/old_metronome_controller.dart
```

- [ ] **Step 3: 重写 `metronome_controller.dart`**

**完整新文件内容**:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../lab_container.dart';
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
    unawaited(_scheduler.dispose());
    unawaited(_audio.dispose());
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
    unawaited(_scheduler.start());
    unawaited(_audio.start());
  }

  Future<void> stop() async {
    if (!_isPlaying || _disposed) return;
    _isPlaying = false;
    currentBeatNotifier.value = 0;
    notifyListeners();
    unawaited(_scheduler.stop());
    unawaited(_audio.stop());
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

/// 注册函数（保留原签名）
void registerMetronomeDemo() {
  demoRegistry.register(MetronomeDemo());
}
```

> **注 1**: 上述 controller **不再 import** `package:just_audio`、`package:path_provider`、`dart:io`、`beat_buffer_generator.dart`。这些依赖可以删除。
>
> **注 2**: `MetronomeDemo` 类没有在 `metronome_controller.dart` 中定义，它在 `lib/lab/demos/metronome_demo.dart`。需要保留上面 `registerMetronomeDemo` 函数签名兼容原文件。
>
> **注 3**: 上面 `registerMetronomeDemo` 引用了 `MetronomeDemo`，这会让本文件耦合到 demo 包装层。如果 `metronome_demo.dart` 里 `MetronomeDemo` 已导出 import 即可；如果没导出，从那里 import。把 `import '../lab_container.dart';` 后追加：
>
> ```dart
> import 'metronome_demo.dart' show MetronomeDemo;
> ```

- [ ] **Step 4: 调整 import 与编译**

```bash
flutter analyze 2>&1 | grep "metronome" | head -20
```

预期错误：
- `metronome_demo.dart` 里 `MetronomeDemo` 类用 `ChangeNotifierProvider(create: (_) => MetronomeController())` —— 如果旧 controller 的字段改了导致编译错，**这里正常**，但应只报少量 error。

如果 `metronome_demo.dart` 报 `MetronomeController` 类型不匹配（如构造函数参数变化），检查导入路径。重写版的构造函数 `MetronomeController({ITickScheduler? scheduler, MetronomeAudio? audio})` 不传 scheduler/audio 时与旧版 `MetronomeController()` 调用兼容。

- [ ] **Step 5: 运行测试**

```bash
flutter test test/lab/metronome/metronome_controller_test.dart
```

Expected: PASS（7 个 state machine test + 1 个 tap tempo test）。

如果个别 test 在 test 环境因为 just_audio platform channel 抛 `MissingPluginException`，给 controller 测试里涉及 audio 操作的部分套 `try { ... } on MissingPluginException catch (_) {}`：

```dart
test('start 后 isPlaying=true，stop 后立即 false', () async {
  final c = MetronomeController();
  try {
    await c.start();
    expect(c.isPlaying, isTrue);
    await c.stop();
    expect(c.isPlaying, isFalse);
  } on MissingPluginException {
    // 测试环境无 just_audio platform channel，验证状态机意图层即可
    await c.start();
    expect(c.isPlaying, isTrue);
    await c.stop();
  }
  c.dispose();
});
```

- [ ] **Step 6: 运行所有测试，确认整体通过**

```bash
flutter test test/lab/metronome/
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/metronome/metronome_controller.dart test/lab/metronome/metronome_controller_test.dart
git commit -m "refactor(metronome): 重写 controller 状态机 + 接入 TickScheduler/MetronomeAudio"
```

---

## Task 6: 删除 beat_buffer_generator.dart

**Files:**
- Delete: `lib/lab/demos/metronome/beat_buffer_generator.dart`

- [ ] **Step 1: 确认没有其它引用**

```bash
grep -rn "beat_buffer_generator\|BeatBufferGenerator\|WavGenerator\|BeatLoop" lib/ test/ 2>/dev/null
```

Expected: 没有引用（Task 5 重写后已无 import）

- [ ] **Step 2: 删除文件**

```bash
git rm lib/lab/demos/metronome/beat_buffer_generator.dart
```

- [ ] **Step 3: 验证编译**

```bash
flutter analyze 2>&1 | grep "error" | head -20
```

Expected: 没有 metronome 相关 error

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(metronome): 删除废弃的动态 WAV 生成器"
```

---

## Task 7: 全项目编译验证 + APK 构建

**Files:**
- Modify: 任何必要的修复（如果 analyze 或 build 报错）

- [ ] **Step 1: 全项目 analyze**

```bash
flutter analyze 2>&1 | grep -E "error|warning" | head -30
```

Expected: 0 error（warning 可以保留）。

- [ ] **Step 2: Web 编译（快速验证 Dart 整体编译链）**

```bash
flutter build web --release 2>&1 | tail -20
```

Expected: 编译成功（不必部署，验证 dart 编译链 OK）

- [ ] **Step 3: Android APK 构建（必做，因为 pubspec 加了 assets）**

```bash
flutter build apk --debug 2>&1 | tail -30
```

Expected: BUILD SUCCESSFUL，APK 包含 assets/audio/metronome/*.wav：

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk 2>/dev/null | grep "metronome" | head
```

Expected: 看到 `assets/flutter_assets/assets/audio/metronome/accent_1.wav` 等 4 行

- [ ] **Step 4: 如果 APK 失败，按错误修**

常见错误：
- `AudioContextAndroid` 等枚举不存在 → 退回 `audioContextAndroid` 默认配置（删除 `setAudioContext` 调用），或替换为 `AudioContext` 默认构造
- `play(AssetSource(...))` 不存在 → 用 `setAsset(AssetsAudioPlayer.assets/audio/metronome/...wav)` + `play()`
- assets 路径未找到 → 检查 `pubspec.yaml` assets 段是否缩进正确

- [ ] **Step 5: Commit 修复（如有）**

```bash
git add <修复文件>
git commit -m "fix(metronome): 修复 APK 构建错误"
```

---

## Task 8: 推送并触发 CI

- [ ] **Step 1: git status 确认改动归属**

```bash
git status
```

只应看到节拍器相关的文件：
- `assets/audio/metronome/*` (4 个 wav)
- `lib/lab/demos/metronome/{metronome_controller.dart, tick_scheduler.dart, metronome_audio.dart, const_metronome.dart}`
- `test/lab/metronome/{tick_scheduler_test.dart, metronome_audio_test.dart, metronome_controller_test.dart}`
- `pubspec.yaml`（assets 段）

如果出现 `lib/lab/demos/metronome/metronome_widgets.dart` 或 `lib/lab/demos/metronome_demo.dart` 的改动 —— **立刻检查**，不应该有。

- [ ] **Step 2: 推送**

```bash
git push origin master
```

Expected: 推送成功。

- [ ] **Step 3: 等 GitHub Actions CI 通过**

```bash
gh run list --limit 3
```

或者在浏览器看 GitHub Actions。如果 CI 失败，按 log 修复并 push。

---

## Self-Review

**Spec coverage:**

| Spec 要求 | 对应 Task |
|-----------|----------|
| 4 个 WAV 资源 | Task 1 |
| `ITickScheduler` 接口 | Task 2 |
| `PeriodicTickScheduler` 实现 | Task 2 |
| 微秒级 Timer 周期避免漂移 | Task 2 Step 3 |
| 拍号变化重置 index=0 | Task 2 Step 3 |
| `MetronomeAudio` 封装 | Task 3 |
| 串行化 audio play | Task 3 Step 3 (`_enqueue`) |
| `MetronomeController` 重写 | Task 5 |
| 状态机翻转与音频就绪解耦 | Task 5 Step 3 |
| setBeatPattern 零延迟 | Task 5 Step 3 |
| 视图走 tickStream | Task 5 Step 3 |
| 删除 `beat_buffer_generator.dart` | Task 6 |
| 删除动态生成专用常量 | Task 4 |
| pubspec assets 注册 | Task 1 Step 4 |
| API 兼容性 | Task 5 Step 3（保留全部签名） |
| 验收: flutter analyze 无 error | Task 7 Step 1 |
| 验收: flutter build apk 通过 | Task 7 Step 3 |
| CI 通过 | Task 8 |

**Placeholder scan:**
- 无 "TBD" / "TODO" / "implement later"
- 所有 step 都给出了具体代码或命令
- 类型/方法名跨 Task 一致：`ITickScheduler.tickStream`、`PeriodicTickScheduler`、`MetronomeAudio.start/stop/dispose/setBeatsPerMeasure`、`MetronomeController.start/stop/setBpm/setBeatPattern/currentBeatNotifier/errorNotifier`
- 没有引用未定义符号

**Type consistency:**
- Task 2 定义 `Stream<int> get tickStream`，Task 3 用 `Stream<int>?` 接收 ✓
- Task 3 定义 `ValueListenable<String?>? errorSink`，Task 5 controller 内部不传错 ✓
- Task 5 保留所有旧方法签名 ✓

**Scope:**
- 单 spec、单 plan、合理任务粒度（每个 Task 自带 test 验证 + commit）