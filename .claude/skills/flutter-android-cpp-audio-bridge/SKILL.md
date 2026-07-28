---
name: flutter-android-cpp-audio-bridge
description: Flutter Android 项目需要低延迟/高精度音频同步（节拍器、节奏游戏、节拍同步动画、卡拉OK、鼓机）时，通过 C++ Oboe + FFI 桥接原生音频层。触发词：节拍器、metronome、音频卡顿、视图声音不同步、native 音频、Oboe、AAudio、FFI 音频、低延迟音效。
---

# Flutter Android C++ 音频桥接 Skill

## 何时用

Flutter 项目里出现以下任一情况时，必须走本 skill 路线：

| 症状 | 含义 |
|------|------|
| bpm > 250 的节拍器听上去漂移 | Timer.periodic 在 Dart 单线程里有 jitter |
| 视图指示灯和声音错位几毫秒~几十毫秒 | 视觉/音频时钟不同源 |
| App 切到后台节拍器停了/漂了 | Dart Timer 被 Doze 冻结 |
| 多声部节奏游戏音画不同步 | UI 60fps vs 音频独立时钟 |
| 用户明确要求"用 C 实现准确声音" | 直接命中本 skill |

**反之不需要**：普通一次性音效播放（用 just_audio/audioplayers 就够）、短提示音、纯音乐播放器。

## 何时读 ref（按需加载）

| ref | 何时读取 |
|-----|----------|
| [[oboe-cpp-synthesis]] | 想知道 C++ Oboe audio callback 怎么工作 / 实时 sin 合成的数学 / sampleCounter 为什么要 `=` 而不是 `-=` / 衰减包络怎么算 / 钳位为什么必要 |
| [[android-native-c-setup]] | 对 Android 原生层不熟：CMake/Gradle 怎么搭、ABI 多架构、FFI vs JNI 选型、库加载机制、extern "C" 作用、常见构建错误排查 |
| [[wav-sample-playback]] | 需要自定义拍声音色：不想用纯合成 tone、想用 WAV 采样替代 click/木鱼/鼓、或让用户上传自己的 wav 作为拍声 |

## 核心架构

```
┌─ C++ Audio Thread (Oboe) ─────────────────────┐
│  AudioStreamCallback::onAudioReady(sample):    │
│    sampleCounter >= samplesPerBeat              │
│      → 实时合成 click sample 写入 audio buffer │
│      → tickCallback(beatIndex)  ← 唯一 tick 源 │
└────────────┬───────────────────────────────────┘
             ↓ (NativeCallable, dart:ffi)
┌─ Dart UI Isolate ──────────────────────────────┐
│  MetronomeFFI._onNativeTick(int)                │
│    → StreamController.add(beatIndex)            │
│      ↓                                          │
│  MetronomeController._tickSub                   │
│    → currentBeatNotifier.value = beatIndex      │
│    → UI rebuild BeatIndicator dot               │
└─────────────────────────────────────────────────┘
```

**关键**：音频和 tick 在同一个 native audio callback 里 emit，物理上不可能脱钩。

原理详见 [[oboe-cpp-synthesis]] 第 2、3、4 节。

## 实施 SOP（6 步）

### 1. 创建 cpp 目录骨架

```bash
mkdir -p android/app/src/main/cpp
```

### 2. 三个 cpp 文件

| 文件 | 内容 |
|------|------|
| `metronome.h` | C 接口声明：`init_audio` / `play` / `pause` / `set_bpm` / `set_beats_per_bar` / `set_tick_callback` |
| `metronome.cpp` | `class Metronome : public AudioStreamCallback`，全局 `gMetronome` + `gStream`，`extern "C"` 暴露给 FFI |
| `CMakeLists.txt` | `find_package(oboe REQUIRED CONFIG)` + `target_link_libraries(metronome oboe::oboe log)` |

**参考样板**：照抄本项目已落地的 `android/app/src/main/cpp/metronome.{h,cpp}` + `dr_wav.h`（`lib/services/metronome/` 是 Dart 端 FFI facade）。已实现 wav sample slot、合成 fallback、跨页面共享 service、单例 stream。

**完整 CMakeLists / Gradle 配置语法**：见 [[android-native-c-setup]] 第 2、3 节。

### 3. Android Gradle 配置（最小版）

`android/app/build.gradle.kts`：

```kotlin
android {
    defaultConfig {
        externalNativeBuild {
            cmake { arguments("-DANDROID_STL=c++_shared") }
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    buildFeatures { prefab = true }
}

dependencies {
    implementation("com.google.oboe:oboe:1.10.0")
}
```

**ABI 选择、proguard 规则、native 方法 keep**：见 [[android-native-c-setup]] 第 4、13 节。

### 4. Dart FFI Binding（最小版）

`lib/<feature>/ffi_bindings.dart`：

```dart
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

typedef _NativeTick = Void Function(Int32);
typedef _DartTick = void Function(int);
typedef _InitAudioNative = Void Function(Double);
typedef _InitAudioDart = void Function(double);
// ... 每个 C 函数一对

class MetronomeFFI {
  static final DynamicLibrary _lib = Platform.isAndroid
      ? DynamicLibrary.open("libmetronome.so")
      : throw UnsupportedError("Only Android is supported");

  static final _initAudio = _lib.lookupFunction<_InitAudioNative, _InitAudioDart>('init_audio');
  // ... 更多

  static NativeCallable<_NativeTick>? _tickCallable;
  static final StreamController<int> _controller = StreamController<int>.broadcast();
  static Stream<int> get tickStream => _controller.stream;

  static void init(double bpm) {
    if (_tickCallable != null) return;
    _initAudio(bpm);
    _tickCallable = NativeCallable<_NativeTick>.listener(_onNativeTick);
    _setTickCallback(_tickCallable!.nativeFunction);
  }

  static void _onNativeTick(int beatIndex) {
    if (_controller.isClosed) return;
    _controller.add(beatIndex);
  }
}
```

**关键**：
- `_tickCallable` 必须在 `_setTickCallback` 之前构造（C++ 在 audio thread 拿函数指针）
- `NativeCallable.listener` 不是 `.isolateLocal`
- 不需要 `package:ffi` —— `dart:ffi` 够用

### 5. Controller 写状态机

```dart
class MetronomeController extends ChangeNotifier {
  MetronomeController() {
    _tickSub = MetronomeFFI.tickStream.listen((beatIndex) {
      currentBeatNotifier.value = beatIndex;
    });
    MetronomeFFI.init(120);
  }

  void setBpm(int bpm) {
    _bpm = bpm;
    MetronomeFFI.setBpm(bpm.toDouble());
    notifyListeners();
  }

  void start() { _isPlaying = true; notifyListeners(); MetronomeFFI.play(); }
  void stop() { _isPlaying = false; notifyListeners(); MetronomeFFI.pause(); }

  void dispose() {
    _tickSub?.cancel();
    MetronomeFFI.shutdown();
    super.dispose();
  }
}
```

### 6. 音色差异化（节拍器必读）

强弱次强要"听感明显"必须 4 维同步拉开（详见 [[oboe-cpp-synthesis]] 第 5 节）：

| 维度 | weak | medium | accent |
|------|------|--------|--------|
| 频率 | 700 Hz | 1400 Hz | 2200 Hz |
| 振幅 | 0.4 | 0.7 | 1.0 |
| 时长 | 200 sample | 200 sample | 300 sample |
| 谐波 | 无 | 2x | 2x + 3x |

cpp 端用 `beatAccentLevels[beatsPerBar]` 数组，Dart 在 `setBeatPattern` 时循环 `setBeatAccentLevel(i, level)` 注入。

**用真实采样替代合成音色**：走 [[wav-sample-playback]]。加载 WAV 后，对应 slot 的拍子播采样，其余保持合成。」

## 验证流程

1. `flutter analyze lib/` → 必须 0 error
2. **必须** `flutter build apk --debug` 验证 native 链路（analyze 看不到 CMake/oboe 链接问题）
3. push → 等 GitHub Actions CI
4. 装机实测

**构建错误排查清单**：见 [[android-native-c-setup]] 第 13 节。

## good_eg (成功案例)

| 场景 | 做法 | 结果 |
|------|------|------|
| 本项目节拍器重构 2026-07-27 | 在本项目 cpp 目录直接落 metronome.h/cpp + Dart FFI，初始化即跑通 | CI 一次通过，bpm 250+ 仍稳 |
| 强弱次强音色差异化 | 4 维（频率+振幅+时长+谐波）同步拉开 | 听感三档清晰可辨 |
| 节拍器 demo 退出后 clock demo 没声 | 双实例 Oboe stream + sample slot 各自释放 | 抽 MetronomeService 单例，stream 跟 app 进程 |
| 用户在独立节拍器设的木鱼 → 进 clock demo 不见了 | controller dispose 关 stream + free slots | sample 跨页面持久，stream 不主动关 |
| 架构选型先列 3 方案 + 让用户决策 | Timer / Oboe / Service 三选一 | 避免猜错返工 |

## bad_eg (失败案例)

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|--------|
| 先走 Timer+Dart 方案（bpm=180 边界勉强能用） | 后台冻结、视图声音漂移、用户再次要求重做 | 直接 Oboe+FFI，不走弯路 |
| 凭印象写 `AudioContextAndroid` / `AssetSource` | 那是 audioplayers 的 API，just_audio 不存在 | 先 grep 实际包源文件 |
| 多次 `flutter build apk` 验证"小改动" | 用户拒绝、浪费时间、analyze 已足够 | analyze + CI 二段验证，别本地 build |
| 用 `Timer.periodic((60000/bpm).round() ms)` 整毫秒 | 每拍 +1ms 累积，1 分钟偏移半拍 | 用 `Duration(microseconds: ...)` 微秒级 |
| `package:ffi/ffi.dart` import | pubspec 没直接依赖，会 warn | `dart:ffi` 已够用 |
| NativeCallable 在 setTickCallback 之后才创建 | C++ 在 audio thread 拿不到函数指针崩 | 严格顺序：构造 callable → 注入 nativeFunction |
| `sampleCounter = 0` 直接清零 | 一拍位置精确度差 ±numFrames | `sampleCounter -= samplesPerBeat` 保留余数（详见 [[oboe-cpp-synthesis]] 第 4 节） |

## 何时该停止用 Oboe 升级

- 跨平台需求出现（iOS/桌面/Web）→ Oboe 不能跨，必须换 web audio / iOS AudioUnit
- bpm 始终 < 80 且是短时使用 → Timer 方案足矣

## 跨平台替代方案

| 平台 | 替代 |
|------|------|
| iOS | AudioUnit + Swift C bridge（Oboe 仅 Android） |
| Web | Web Audio API `AudioContext` + AudioWorklet |
| Desktop | miniaudio 或 SDL_audio |

## 相关参考资料

- 本项目已实现的 C++ Oboe + Dart FFI 范例：`android/app/src/main/cpp/metronome.{h,cpp}` + `dr_wav.h` + `lib/services/metronome/metronome_service.dart`
- Oboe 官方文档: https://github.com/google/oboe
- dr_wav 单头解码库（public domain）：https://github.com/mackron/dr_libs/blob/master/dr_wav.h

---

## Ref 索引

| ref | 主题 | 行数 |
|-----|------|------|
| [[oboe-cpp-synthesis]] | C++ Oboe 实时 sin 合成原理（sample 模型 / 回调机制 / 相位累加器 / 包络数学 / 钳位 / PerformanceMode） | ~200 |
| [[android-native-c-setup]] | Android 原生 C 编码原理（CMake/Gradle/ABI/FFI vs JNI/库加载/extern "C"/调试技巧/错误排查） | ~250 |
| [[wav-sample-playback]] | 自定义 WAV 采样拍声音色（3-slot 架构/dr_wav 加载/resample/asset materializer/FFI 传路径/slot 映射陷阱） | ~150 |