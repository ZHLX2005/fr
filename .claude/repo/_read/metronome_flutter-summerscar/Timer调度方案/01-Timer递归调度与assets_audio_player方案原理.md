# summerscar metronome — Timer 调度方案与预录制音频方案原理

> 来源仓库: `.claude/repo/metronome_flutter-summerscar/lib/main.dart`

## 1. 核心调度算法 — 单次 Timer + 递归

`main.dart:83-88`:

```dart
void runTimer() {
  timer = Timer(Duration(milliseconds: (60 / _bpm * 1000).toInt()), () {
    _playAudio().then((value) => _setNowStep());
    runTimer();
  });
}
```

**核心思想**:不使用 `Timer.periodic`,而是用**单次 Timer 在回调内递归 schedule 下一次**。

### 为什么是单次而非周期?

- BPM 可能动态改变。`Timer.periodic` 的 period 一旦设定无法修改;一旦创建就会按旧 period 一直触发
- 单次 Timer + 递归,每次重新计算 `Duration(milliseconds: (60 / _bpm * 1000).toInt())`,总是用最新 BPM
- `60 / BPM × 1000` 给出的就是**单拍毫秒数** — BPM 60 → 1000ms 间隔

### 节拍触发时序

```
t=0       t=interval       t=2×interval  ...
│         │                │
start     ┌──────────────┐
│         │ Timer fires   │
│         ├─ _playAudio() │  ← 异步播音频
│         │   await open()│  ← 异步 IO
│         ├─ _setNowStep()│  ← setState → 刷新 Indactor
│         └─ runTimer()   │  ← 排下一次
└─────────┴────────────────┘
```

`_playAudio().then((value) => _setNowStep())` 用 `.then` 等待 mp3 open 完成再 setState,所以**视觉更新会在音频开始之后**(`assets_audio_player.open` 是异步 IO)。

## 2. 调度精度的实际局限

**Timer 单次触发精度** 由 `dart:async` Timer 决定,在 Flutter 主 isolate 受:

- Frame 调度影响(典型 60Hz / 16.7ms)
- GC / 主线程长任务导致延迟
- _playAudio 异步打开 mp3 又有额外延迟

实际累计抖动可达 **10-50ms**,对练耳节奏训练来说偏高。**这就是为何 MateusNavarro77 改用 Oboe Native C++ 路线**。

但 summerscar 的实现:

- 优点:代码极简 (30 行核心),逻辑一目了然,跨端 (Android/iOS/Web) 一致
- 适用:教学 demo / 业余练耳 / 不需要专业级精度的场景

## 3. 音频播放 — `assets_audio_player.open` 模式

`main.dart:74-81`:

```dart
Future<void> _playAudio() {
  int nextStep = _nowStep + 1;
  if (nextStep % 4 == 0) {
    return assetsAudioPlayer.open(Audio('assets/metronome$soundType-1.mp3'));
  } else {
    return assetsAudioPlayer.open(Audio('assets/metronome$soundType-2.mp3'));
  }
}
```

### 关键设计

- 每次播放都是 `assetsAudioPlayer.open(Audio(...))`,**打开并播放一个音频**
- 重音 vs 普通音硬编码 4 拍:`% 4 == 0` → `-1.mp3`(重音),否则 `-2.mp3`(普通)
- 不同音效:`soundType` 切换 `metronome0-` / `metronome1-` 前缀

### 为什么不用 preloaded AudioPlayer?

也可以启动时一次性加载所有音频到内存,运行时调用 `play()`,避免 `open()` 重复 IO。但这个仓库用了最简方案 — 每次 `open`。

## 4. UI 与状态同步 — `setState` 路径

`main.dart:68-72`:

```dart
void _setNowStep() {
  setState(() {
    _nowStep++;
  });
}
```

`_nowStep` 是单调递增计数器,UI 通过 `(nowStep % steps.length)` 决定哪个圆点高亮(`indactor.dart:21-23`):

```dart
color: this.nowStep > -1 &&
        (this.nowStep % steps.length) == entry.key
    ? Color.fromARGB(255, 102, 204, 255)   // 激活蓝
    : Colors.grey[300]
```

### 关键点

- `_nowStep` 初始化为 `-1`,startTimer 后 `_nowStep+1=0` 触发"第 1 拍"激活
- 由于 `_nowStep` 不重置,运行久了会**单调递增超出 int 范围** — 但实际 BPM 250 跑 100 天才会达到 int 限制,可忽略
- `_nowStep % steps.length` 用模运算实现"循环 4 拍"

## 5. Toggle 切换

`main.dart:55-66`:

```dart
void _toggleIsRunning() {
  if (_isRunning) {
    timer.cancel();
    _animationController.reverse();
  } else {
    runTimer();
    _animationController.forward();
  }
  setState(() {
    _isRunning = !_isRunning;
  });
}
```

- 停止:`timer.cancel()` — Dart Timer 不会自动 resume
- `_animationController.reverse()` — 动画从正向播回原点(暂停图标 → 播放图标)
- 由于单次 Timer 模式,start 必须重新 `_setBpm` (其实这里直接读 `_bpm`,因为已经在 state),然后 `runTimer()`

### 注意:`runTimer` 内部直接读 `_bpm`

```dart
void runTimer() {
  timer = Timer(Duration(milliseconds: (60 / _bpm * 1000).toInt()), () {
```

`_bpm` 是 state 字段,被 SliderRow `_setBpmHanlder` (`slider.dart` 内的 onChange) 实时更新。这条 path 走 `setState` → rebuild → 此刻 `runTimer` 已经在执行,下次回调触发时拿的是最新 `_bpm`。但**正在等待的 timer 周期不会因 BPM 改变而缩短** — 这是单次 Timer 模式的固有局限。

## 6. 持久化策略

### BPM 持久化

`slider.dart:54-58` 写在 `onChange` 回调,每次拖动都写:

```dart
onChange: (double value) {
  setBpmHandler(value.toInt());
  _storeBpm(value.toInt());   // 每次都写 SharedPreferences
},
```

`_storeBpm` 写 SharedPreferences,但**只在拖动停止时写入**,频率较高时 IO 也较高。可优化:加 `debounce`,但极简实现没做。

### 音效持久化

`setting.dart:84-88`:

```dart
_setSoundType(int soundtype) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setInt('sound', soundtype);
}
```

仅在用户选择时写一次。

### 启动恢复

`main.dart:108-118`:

```dart
@override
void initState() {
  super.initState();
  if (!kIsWeb) {
    Wakelock.enable();
  }
  setSoundType();
  setBpm();
  _animationController =
      AnimationController(vsync: this, duration: Duration(milliseconds: 300));
}
```

`setSoundType()`、`setBpm()` 各自从 SharedPreferences 读 → 写入当前 state。

## 7. 跨端兼容要点

| 关注 | 实现 |
|------|------|
| Web 不支持 Wakelock API | `if (!kIsWeb) Wakelock.enable();` (`main.dart:111-113`) |
| assets_audio_player 多端 | 同一份代码可用于 Android/iOS/Web |
| 调试打印 | `print('get bpm $bpm')` Web 也无副作用 |

## 8. 与 MateusNavarro77 方案的对比

| 维度 | summerscar (Timer + assets_audio_player) | MateusNavarro77 (Oboe + sin 合成) |
|------|------------------------------------------|-------------------------------------|
| 实现复杂度 | ★☆☆ 极简,30 行核心 | ★★★ C++/Oboe/CMake,多文件 |
| 跨端覆盖 | ★★★ Android + iOS + Web (Web 在线 demo) | ★ Android 优先 (iOS 仅 UI,Web 不可) |
| 调度精度 | ★★ 主线程 Timer + GC 抖动 | ★★★ Oboe 音频回调,亚毫秒级 |
| 音频资源体积 | 需要 4-5 个 mp3 (~几十 KB-几 MB) | 0 字节,程序化合成 |
| 音色可控性 | 受 mp3 采样限制 | 频率/包络/音量可任意改 |
| 调试难度 | 纯 Dart,热重载 | 改 C++ 必须重新 build APK |
| 适合场景 | 教学 / 原型 / Web demo | 专业练耳 / 录音棚 |

## 9. 源码引用汇总

- `lib/main.dart:74-88` — `_playAudio` + `runTimer` 核心循环
- `lib/main.dart:55-66` — Play/Pause 切换
- `lib/main.dart:90-106` — 持久化读写
- `lib/component/indactor.dart:1-27` — IndactorRow UI
- `lib/component/slider.dart:5-58` — SliderRow (含持久化写入)
- `lib/component/setting.dart:1-89` — Setting 页 (音效切换)
- `assets/metronome{0,1}-{1,2}.mp3` — 音频资源
