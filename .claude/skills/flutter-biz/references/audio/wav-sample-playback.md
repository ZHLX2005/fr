---
name: wav-sample-playback
description: 在 Oboe audio callback 里混入 WAV 采样替代合成音色 — dr_wav.h 加载、slot 管理、resample、共享 service、UI slot 映射。读完 SKILL.md 的核心架构 + 6 步 SOP 之后、需要自定义拍声音色时加载。~
---

# WAV 采样播放 — 自定义拍声音色

## 适用场景

- 你觉得三档合成音色（weak/medium/accent）太"电子"了，想用真实乐器采样替换
- 你想给不同类型的拍子分配不同音色（比如 1/4 用木鱼、4/4 保持合成）
- 你想让用户能上传自己的 wav 文件作为拍声音色
- 你有多个页面/组件要共用同一个 Oboe stream + 已加载的 samples

**前提**：你已经有一个跑通的 Oboe bridge（SKILL.md 的 6 步 SOP 已经做完）。本 ref 是在既有 `onAudioReady` 回调里叠加采样层，并配合一个 Dart 单例 service 来跨页面共享。

---

## 核心架构

```
每个拍子触发时:
  onAudioReady 的 sampleCounter >= samplesPerBeat
      ↓
  计算该拍的重音级别 (0=weak, 1=medium, 2=accent)
      ↓
  ┌─ 该 level 有 WAV 加载？ ─→ 播放 gSlots[level].pcm
  │                             采样走完自动 idle
  └─ 无 → 回退到合成 Tone（frequency + harmonics + envelope）
```

```
C++ 侧                                     Dart 侧
gSlots[3] (静态、全进程共享)                MetronomeService.instance（单例）
  ├─ pcm: float*                              ensureReady() ─→ init_audio(bpm)
  ├─ lengthSamples: int                        ↓
  └─ playPos: int                            tickStream (广播流)
       (-1 = idle)                          SampleLoader.materializeAsset()
                                               → rootBundle.load → 写文件
                                             loadSample(level, path)
                                               → utf8 → null-terminated → C
```

**整个 app 生命周期内只有一份 Oboe stream + 一组 sample slot**，由 `MetronomeService` 持有。任何 controller / demo 页面退出都不影响它们。

## C++ 3-slot 模型

```cpp
struct SampleSlot {
    float* pcm = nullptr;     // 解码后的 float32 mono 采样（已重采样到 stream 的 sampleRate）
    int lengthSamples = 0;    // pcm 总数
    int playPos = -1;         // -1 = idle，≥0 = 正播放到第几个采样
};
static SampleSlot gSlots[3];  // 0=weak, 1=medium, 2=accent
```

### 触发逻辑（onAudioReady 每帧判断）

```cpp
if (sampleCounter >= samplesPerBeat) {
    int idxInBar = beat % beatsPerBar;
    int level = beatAccentLevels[idxInBar];  // 0/1/2
    applyTone(level);  // 合成参数就位（不一定播放）
    // WAV slot 优先：有采样则武装，同时关掉合成 click
    if (level >= 0 && level <= 2 && gSlots[level].pcm) {
        gSlots[level].playPos = 0;
        clickRemaining = 0;  // 禁止本次合成
    }
}
// 混音阶段
float sample = 0;
for (int s = 0; s < 3; s++) {         // 所有正在播放的 slot
    if (gSlots[s].playPos >= 0) {
        sample += gSlots[s].pcm[gSlots[s].playPos++];
        if (gSlots[s].playPos >= gSlots[s].lengthSamples)
            gSlots[s].playPos = -1;   // 播完自动 idle
    }
}
if (clickRemaining > 0) {             // 合成 fallback
    sample += /* sin + harmonics + envelope */;
}
// 钳位到 [-1, 1]
```

## WAV 加载函数

```cpp
static bool loadSampleInto(int level, const char* path, double targetSampleRate) {
    unsigned int channels, sampleRate;
    drwav_uint64 totalPCMFrames;
    // 解码为 float32（dr_wav 处理所有格式转换）
    float* raw = drwav_open_file_and_read_pcm_frames_f32(
        path, &channels, &sampleRate, &totalPCMFrames, nullptr);

    // Downmix 多声道 → mono（取平均）
    float* mono = ...;
    for (int i = 0; i < inFrames; i++)
        mono[i] = avg(raw[i*channels + 0..channels-1]);

    // 线性插值 resample 到 Oboe stream 的 sampleRate
    if ((double)sampleRate != targetSampleRate) {
        const double ratio = targetSampleRate / sampleRate;
        for (int i = 0; i < outFrames; i++)
            out[i] = lerp(mono[floor(idx)], mono[ceil(idx)], frac);
    }

    freeSlot(level);                  // ← 热替换前先释放旧 pcm
    gSlots[level].pcm = out;
    gSlots[level].lengthSamples = outFrames;
}
```

### C 接口

```c
int load_sample(int level, const char* path);   // 返回 1/0
void clear_sample(int level);                   // 释放 slot

// shutdown_audio() 不要 free gSamples — samples 是用户配置，应该跨
// stream 生命周期保留。显式卸载通过 clear_sample() 或下一次 load_sample()。
```

## Dart 单例 Service（跨页面共享）

**关键架构决策**：Oboe stream + sample slots 必须是 app 进程级单例，不能绑定到任何 Controller 的生命周期。

```dart
// lib/services/metronome/metronome_service.dart
class MetronomeService {
  MetronomeService._();
  static final MetronomeService instance = MetronomeService._();

  bool _initialized = false;
  final StreamController<int> _tickStreamController =
      StreamController<int>.broadcast();

  void ensureReady({double bpm = 120.0}) {
    if (_initialized) return;
    _initAudio(bpm);  // cpp init_audio
    _tickCallable = NativeCallable<_NativeTick>.listener(_onNativeTick);
    _setTickCallback(_tickCallable!.nativeFunction);
    _initialized = true;
  }

  bool loadSample(int level, String path) {
    // utf8 + null-terminated → calloc<Uint8> → call _loadSample
    // service 持有路径？否。path 是资产缓存路径，下一次启动时再读。
  }

  void clearSample(int level) => _clearSample(level);
  // ... play/pause/setBpm/setBeatsPerBar/setBeatAccentLevel
}
```

`MetronomeFFI`（原静态门面）变成**瘦壳**，所有静态方法转发到 `MetronomeService.instance`。这样老代码不动，新代码直接用 service。

```dart
// lib/lab/demos/metronome/ffi_bindings.dart
class MetronomeFFI {
  MetronomeFFI._();
  static MetronomeService get _svc => MetronomeService.instance;
  static Stream<int> get tickStream => _svc.tickStream;
  static void init(double bpm) => _svc.ensureReady(bpm: bpm);
  // ... 其他都是 _svc.xxx 的转发
}
```

## Asset → 文件系统 Materializer

Flutter assets 藏在 apk 里，`fopen` 读不到真实路径。需要在 Dart 侧先拷贝到应用私有目录：

```dart
// lib/lab/demos/metronome/sample_loader.dart
class SampleLoader {
  static Future<String> materializeAsset(String assetKey) async {
    final data = await rootBundle.load(assetKey);
    final dir = await getApplicationSupportDirectory();
    final outDir = Directory('${dir.path}/metronome_samples');
    if (!await outDir.exists()) await outDir.create();
    final outPath = '${outDir.path}/${assetKey.split('/').last}';
    await File(outPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
    return outPath;
  }
}

// 调用：
final path = await SampleLoader.materializeAsset('assets/audio/woodfish.wav');
MetronomeService.instance.loadSample(level, path);  // level: 0=weak, 1=medium, 2=accent
```

## Per-Level Sound 配置（Controller 层）

`MetronomeController` 维护每个 slot 的声音配置：

```dart
static const int soundSynth = 0;    // 默认空
static const int soundWoodfish = 1; // 木鱼 WAV
final List<int> _soundIds = [0, 0, 0];  // per level: [weak, medium, accent]

Future<bool> setSoundForLevel(int level, int soundId) async {
  if (soundId == soundSynth) {
    MetronomeService.instance.clearSample(level);
  } else {
    final path = await SampleLoader.materializeAsset('assets/audio/woodfish.wav');
    MetronomeService.instance.loadSample(level, path);
  }
  _soundIds[level] = soundId;
  notifyListeners();
}
```

## UI 展示 key: Slot Index 映射陷阱

**C++ slot 索引固定**：`0=weak, 1=medium, 2=accent`

但 UI 展示顺序通常是 accent → medium → weak（用户期望"强拍"排第一）。如果直接按 `for (int i = 0; i < 3; i++)` 传索引，会导致**显示为"强拍"的下拉把采样加载到了 C++ weak slot**。

```dart
// 映射层 — 必须加
const uiToCppSlot = [2, 1, 0];  // UI行序(accent→med→weak) → C++ slot
// 用 uiToCppSlot[displayIdx] 取真实 slot 索引
controller.soundForLevel(uiToCppSlot[displayIdx]);
```

## 文件清单

| 层 | 文件 | 作用 |
|----|------|------|
| C++ header | `metronome.h` | `load_sample` / `clear_sample` 声明 |
| C++ impl | `metronome.cpp` | SampleSlot, dr_wav 加载, onAudioReady 混音 |
| C++ lib | `dr_wav.h` | 单头 wav 解码库（public domain） |
| **Dart service** | `lib/services/metronome/metronome_service.dart` | **Oboe stream + sample slots 单例持有者** |
| **Dart service facade** | `lib/services/metronome/metronome.dart` | export |
| Dart FFI facade | `lib/lab/demos/metronome/ffi_bindings.dart` | 瘦壳，转发到 service（兼容老代码） |
| Dart asset | `lib/lab/demos/metronome/sample_loader.dart` | asset → 文件系统拷贝 |
| Dart controller | `lib/lab/demos/metronome/metronome_controller.dart` | `setSoundForLevel` per-level API |
| Dart UI | `lib/lab/demos/metronome_demo.dart` | 音色选择器（带 ui→cpp slot 映射） |
| Asset | `assets/audio/woodfish.wav` | 默认木鱼采样 |

## good_eg (成功实践)

| 做法 | 结果 |
|------|------|
| `MetronomeService.instance` 单例持有 stream + slots | controller dispose 不影响 stream，sample 跨页面持久 |
| `MetronomeFFI` 瘦壳转发到 service | 老 consumer 代码无需修改即可享受单例好处 |
| `MetronomeController.dispose()` 只调 `pause()`，不调 `shutdown()` | 切换页面不破坏已加载的 samples |
| `shutdown_audio()` 不再 free gSamples | samples 跟随 app 进程而不是 stream 周期 |
| `_ensureReady` 里 fire-and-forget 预加载 | 无感知，首个 beat 靠合成 fallback，后续自动切到采样 |
| dr_wav.h `drwav_open_file_and_read_pcm_frames_f32` 一把解码 | 一次调用完成所有格式转换 + 重采样到 float32 |
| `clear_sample` + free 旧 pcm 再赋值新 pcm | 热替换安全，audio thread 读到的是完整的新 buffer |
| 合成 Tone 永远保留作为 fallback | load 失败时用户完全无感知 |
| SharedPreferences `metronome_slot_{0,1,2}` 持久化 | 用户配置跨重启保留 |

## bad_eg (踩坑记录)

| 错误操作 | 后果 | 正确做法 |
|----------|------|----------|
| `MetronomeController.dispose()` 调 `MetronomeFFI.shutdown()` | 关 stream + 释放 samples，下个页面用不了 | 只 `pause()`；stream 跟随 app 进程 |
| `shutdown_audio()` 把 `gSamples[]` 也 free 掉 | stream 重开后已加载的 woodfish 没了 | shutdown 只关 stream；samples 是用户配置，跨生命周期保留 |
| Oboe stream 跟着 Controller 走（每次 controller new 一个） | 多 controller 各自 stream → 资源浪费 + 配置丢失 | service 单例，stream 跟 app 进程 |
| 静态类持有 stream（`MetronomeFFI` 直接管） | 多调用方 unclear 谁负责 dispose | 抽单例 `MetronomeService`，原 facade 变瘦壳 |
| UI 行序直接传给 `loadSample(level, path)` | 选"强拍"实际加载到 weak slot | 加 `uiToCppSlot` 映射表 |
| `static const` 写在非类函数体内 | Dart compile error: `extraneous_modifier` | 用 `const` 不加 `static` |
| 用 `_uiToCppSlot`（带下划线）命名局部变量 | Dart lint: `no_leading_underscores_for_local_identifiers` | 局部变量不要下划线前缀 |
| import `package:ffi` 但不加 pubspec 依赖 | `depend_on_referenced_packages` lint warning | 在 pubspec 显式加 `ffi: ^2.1.0` |
| 多个 LabClockProvider 实例各自跑 timer | wipe 一个实例后另一个写回旧数据 | 确保单例；clock_demo 复用 main 的 provider |