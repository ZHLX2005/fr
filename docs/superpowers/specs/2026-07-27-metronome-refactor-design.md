# 节拍器重构设计 spec

- **日期**: 2026-07-27
- **作者**: Claude Opus 4.8
- **关联项目**: xiaodouzi/fr (Flutter Android)
- **状态**: 待用户审核

---

## 1. 背景与现状

当前项目 `lib/lab/demos/metronome/` 下的节拍器 demo 完全不可用。三类故障：

### 1.1 声音无法停止
**根因**：`MetronomeController.start()` 是异步链（`_loadAndPlay` → 写 WAV 临时文件 → `setFilePath` → `play`）。用户按下"播放"后 `_isPlaying` 立即翻 `true`，但音频还在初始化；用户以为没反应又按一下，`stop()` 进队排在 `_loadAndPlay` 后面——而 `_loadAndPlay` 末尾还有一句 `await _audioPlayer.play()`。两个操作之间存在几十到几百毫秒的"音频引擎不知道用户已经反悔"窗口。

此外 `dispose()` 直接 `_audioPlayer.dispose()`，没有先 cancel `_positionSub`，sub 的回调可能在 dispose 后还触发一次 `currentBeatNotifier.value =`，造成 disposed-listener 异常。

### 1.2 拍号无法生效
**根因**：拍号变化走 `_scheduleReload` 140ms 防抖 → 重生成完整循环 WAV → 写临时文件 → `setFilePath`。这条链路慢、且每次 setFilePath 会重置 `position` 到 0。如果用户连点拍号选择器，旧 reload 还在排队新的 reload 就来了，旧 `_positionSub` 已经 cancel 但 `loop` 闭包还引用了上一次的 beatDuration，导致下一拍计算用的分母是错的。

### 1.3 视图与声音不对应
**根因**：`_subscribePosition(BeatLoop loop)` 一次性把 `loop.beatDuration` 抓进闭包。reload 后音频文件换了（BPM/拍号都变了），但 position stream 的回调仍用旧的 beatMicros 除，得出的 beatIndex 偏移一倍以上。

更糟的是 BPM 改动防抖 140ms，但用户拖 Slider 时每秒能触发 60 次 `onChanged`，每次都 cancel+reschedule Timer + notifyListeners，CPU 直接被打爆。

---

## 2. 目标

修复以上三类问题，不引入新依赖、不修改 UI 层（`metronome_widgets.dart` 所有现有 widget 保留），不修改 Android 原生层。

---

## 3. 核心方案：TickScheduler 抽象 + 短音频 assets

### 3.1 思路
把"拍点调度"从音频引擎里彻底分离出来。**音频不再决定拍点，而是响应拍点事件播放音效**：
- 用 `Timer.periodic(60_000 / bpm ms)` 推拍点（自带动相位锁）
- 拍号一变，重置 Timer，重置 currentBeatIndex=0
- 音频播放独立短音效 `tick_short.wav` / `accent_short.wav`（各两个音色变体，备选）

### 3.2 拆出的抽象：`TickScheduler`
```dart
abstract class ITickScheduler {
  bool get isRunning;
  int get currentBeatIndex;
  Stream<int> get tickStream;  // 每拍发射一次，载荷是当前 beatIndex
  void start();
  void stop();
  void setBpm(int bpm);
  void setBeatsPerMeasure(int beats);
}
```

实现：`PeriodicTickScheduler` 用 `Timer.periodic`，内部维护 beatIndex。`start()` 重置 index=0 并启 Timer；`stop()` 取消 Timer 并发 -1 哨兵让 UI 清空指示灯。

### 3.3 音频层：`MetronomeAudio`
不再用"循环播放整段 WAV"。改为：
- 启动时把 4 个 short wav（accent×2 + regular×2）预加载到内存
- 监听 `TickScheduler.tickStream`，每 tick 来就 play 一个 short wav（accent/regular 由 `beatIndex % beatsPerMeasure == 0` 决定）
- 用 `audioplayers` 包的 `AudioPlayer.play(AssetSource(...))` 或 `just_audio` 的 `setAsset + play`（已装 `just_audio`，优先用）
- 多次重叠触发靠 `Mode.lowLatency` + 短缓存

### 3.4 控制器：`MetronomeController` (重写)
持有 `ITickScheduler` + `MetronomeAudio`，对外暴露和现在相同的 API（`bpm`/`isPlaying`/`beatPattern`/`currentBeatNotifier`/`errorNotifier`/`setBpm`/`togglePlay`/`setBeatPattern`/`tap`）。状态机：

| 事件 | _isPlaying 翻转 | 调度器动作 | 音频动作 |
|------|----------------|-----------|----------|
| start() (false→true) | 立即 true, notify | start(), 重置 index=0 | start() 启动监听 |
| stop() (true→false) | 立即 false, notify | stop() | stop() 取消监听 |
| setBpm() (运行中) | 不变 | 重启 Timer with 新周期 | 不变 |
| setBeatPattern() (运行中) | 不变 | 重置 index=0 + 重启 Timer | 不变 |
| setBpm/setBeatPattern() (停止中) | 不变 | 只更新内部参数 | 不变 |

**关键：不再生成任何 WAV 临时文件**。

### 3.5 节拍指示器同步
`currentBeatNotifier` 现在订阅 `tickStream`（不再订阅 `positionStream`）。一拍一更新，绝对不会有偏移。

---

## 4. 文件清单

### 新增
1. `assets/audio/metronome/accent_1.wav` — 强拍音色 1 (~5KB)
2. `assets/audio/metronome/accent_2.wav` — 强拍音色 2 (~5KB)
3. `assets/audio/metronome/regular_1.wav` — 弱拍音色 1 (~5KB)
4. `assets/audio/metronome/regular_2.wav` — 弱拍音色 2 (~5KB)
5. `lib/lab/demos/metronome/tick_scheduler.dart` — ITickScheduler + PeriodicTickScheduler

### 修改
1. `lib/lab/demos/metronome/metronome_controller.dart` — 重写。引入 ITickScheduler + MetronomeAudio，删除 BeatBufferGenerator/BeatLoop/WavGenerator 引用，删除 _queue/_tempWavPath/_reloadDebounce/_initFuture，删除 positionStream。
2. `lib/lab/demos/metronome/metronome_audio.dart` — 新建。封装 just_audio 4 个音效 + 监听 tickStream 触发播放。
3. `lib/lab/demos/metronome/beat_buffer_generator.dart` — 删除（重生成不再需要）
4. `pubspec.yaml` — assets 段加 `assets/audio/metronome/*.wav`
5. `lib/lab/demos/metronome/const_metronome.dart` — `MetronomeDefaults` 删除 `minLoopSec`、`sampleRate`、`clickDurationSec`（重生成专用），其它参数（minBpm/maxBpm/reloadDebounceMs/tapTempo*）保留。

### 不修改
- `lib/lab/demos/metronome/metronome_widgets.dart` — 所有 widget 不动
- `lib/lab/demos/metronome/metronome_demo.dart` — DemoPage 包装不动
- `lib/lab/demos/metronome/const_metronome.dart` — BeatPattern/AccentLevel/AccentVolume/AccentFrequency/AccentColor/MetronomePresets 不动
- 任何 Android 原生文件
- 任何 lab 容器 / 注册代码

---

## 5. 关键设计细节

### 5.1 Timer 重启的安全模式
`setBpm()` 在运行中重启 Timer 时，必须先 cancel 旧的、再启动新的，且新 Timer 的 index 必须从 0 开始（拍号变 + BPM 变都重置，因为相位换了）：
```dart
void _restartTimer() {
  _timer?.cancel();
  _currentBeatIndex = 0;
  currentBeatNotifier.value = 0;
  final periodMs = (60_000 / _bpm).round();
  _timer = Timer.periodic(Duration(milliseconds: periodMs), (_) {
    _currentBeatIndex = (_currentBeatIndex + 1) % _beatsPerMeasure;
    currentBeatNotifier.value = _currentBeatIndex;
    _tickStreamController.add(_currentBeatIndex);
  });
}
```

### 5.2 串行化音频播放
just_audio 的 `play()` 是一次性的，不要重叠触发。给 MetronomeAudio 加一个 `Future` 队列（同当前 `_queue` 模式），保证 audio play 是串行的：
```dart
Future<void> _enqueue(Future<void> Function() op) {
  final next = _audioQueue.then((_) => op());
  _audioQueue = next.catchError((_) {});
  return next;
}
```

### 5.3 拍号变化时 currentBeatNotifier 重置
拍号从小节 4/4 切到 3/4 时，currentBeatIndex=3 已经越界，立刻归 0。setBeatPattern 的 UI 显示逻辑 (`isActive = index == currentBeat && isPlaying`) 不会出现"无对应 dot 高亮"的奇怪状态。

### 5.4 Tap Tempo
保持现有逻辑（`_tapTimes` 滑动窗口 + 平均间隔），仅删除不再需要的 _bpm 校验边界条件。

### 5.5 错误处理
- AudioPlayer 加载失败：在 MetronomeAudio 内部 try/catch，emit 到 `errorNotifier`
- Timer 不可能失败
- 状态机翻转不依赖音频就绪：用户意图层立即生效

### 5.6 暂停 vs 停止
当前 UI 只有 `togglePlay`（按钮）和 `pause`（pause 按钮）。两个都翻 `_isPlaying = false`。行为合并。

---

## 6. 不做（Out of Scope）

- 不做 Wakelock（保持屏幕常亮）—— 原项目用 `wakelock_plus`，但这是 demo 不是必备，删除避免引入新依赖
- 不做首拍重音开关（参考项目有 `useAccentTick`，当前 UI 没有相应按钮）—— 拍号系统已经天然支持首拍 accent
- 不做加速度传感器联动（参考项目也没有）
- 不做音效音色切换 UI（生成 4 个 wav 时已经预置两种音色，UI 不暴露切换）
- 不写 widget 测试（项目惯例，无 flutter_test 测试覆盖）

---

## 7. 验收

1. `flutter analyze` 无 error
2. `flutter build apk` 通过（验证 Android 构建链没坏）
3. 推送 GitHub Actions CI 通过
4. 行为：
   - 按播放：立刻开始响，指示灯从第 1 拍开始闪烁
   - 按停止：立刻停（≤ 100ms 内无声）
   - 连按播放两次：不会出现"两个 start 打架"
   - 拖动 BPM Slider：拍点间隔实时跟随，无"卡一下"
   - 切换拍号（4/4 → 3/4）：指示灯立刻从第 1 拍开始；切回 4/4 也正常
   - Tap Tempo：连续点击，节拍器跟到点击节奏
   - 后退到 lab container：app 不崩、无 disposed-listener 异常

---

## 8. 风险

- **just_audio 短音效延迟**: Android 上 play → 出声有 30-80ms 延迟，与 Timer 周期同步可能产生"拍点视觉比声音早"。**缓解**：用 `Mode.lowLatency`，且 Timer 周期使用 `Duration(microseconds: 60_000_000 / bpm)` 而不是整数毫秒，避免每拍 +1ms 累积漂移。
- **WAV 资源未生成**: 需要现场生成 4 个短 wav（用 `sox` 或 `ffmpeg`），用 16-bit mono 8kHz 截断正弦波。生成脚本放在 `tools/gen_metronome_wav.dart` 一次性执行。
- **player.dispose 时机**: stop 后再 dispose controller，确保 audioQueue 中残留 future 全部 done 后再 dispose AudioPlayer。用 `_disposed` 标志位防止 disposed 后还往 queue 推任务。