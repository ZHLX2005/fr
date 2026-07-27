# MateusNavarro77 metronome — Native 音频引擎 (C++/Oboe) 原理

> 来源仓库: `.claude/repo/metronome-MateusNavarro77/android/app/src/main/cpp/`

## 1. Native 工程结构

```cmake
# 来源: android/app/src/main/cpp/CMakeLists.txt:1-19
cmake_minimum_required(VERSION 3.22.1)
project(metronome)
add_library(metronome SHARED metronome.cpp metronome.h)
find_package(oboe REQUIRED CONFIG)
target_link_libraries(metronome oboe::oboe log)
```

- **编译产物**:`libmetronome.so` (这正是 `lib/ffi.dart:7` 动态加载的文件)
- **依赖**:`oboe::oboe` — Google 的 C++ Oboe 库,专为 Android 低延迟音频设计 (AAudio/OpenSL ES)
- **`log`**:Android 原生日志库

C 接口声明(`android/app/src/main/cpp/metronome.h:1-16`):

```c
typedef void (*TickCallback)(int);
void init_audio(double bpm);
void play_metronome();
void pause_metronome();
void shutdown_audio();
void set_bpm(double bpm);
void set_beats_per_bar(int beatsPerBar);
void set_tick_callback(TickCallback callback);
void set_use_accent_tick(bool useAccentTick);
```

`extern "C"` 保证符号名不会被 C++ name mangling,Dart 端 `dart:ffi` 才能匹配。

## 2. 核心调度算法 — sample 计数器

节拍精度决定于 `samplesPerBeat`(`metronome.cpp:9-19`):

```cpp
// 来源: android/app/src/main/cpp/metronome.cpp:9-19
double bpm = 120.0;
double sampleRate = 48000.0;
int beatsPerBar = 4;
bool useAccentTick = false;

const float accentTickFrequency = 1500.0;
const float regularTickFrequency = 1000.0;

double samplesPerBeat;
double sampleCounter = 0;
```

每次 BPM 变化都会更新定时(`metronome.cpp:33-35`):

```cpp
// 来源: android/app/src/main/cpp/metronome.cpp:33-35
void updateTiming() {
    samplesPerBeat = sampleRate * 60.0 / bpm;
}
```

`60.0 / bpm` 是单拍秒数,乘以 `sampleRate` 得到单拍样本数。**这是音频合成的核心**:不依赖 `Timer`,而是用音频回调流累计 sample,精度远高于软件定时器。

## 3. Oboe 音频流初始化

`init_audio` 使用 Oboe `AudioStreamBuilder`(`metronome.cpp:130-149`):

```cpp
// 来源: android/app/src/main/cpp/metronome.cpp:130-149
void init_audio(double bpm) {
    if (gStream) return;
    gMetronome = new Metronome(bpm);

    AudioStreamBuilder builder;
    builder.setDirection(Direction::Output);
    builder.setPerformanceMode(PerformanceMode::LowLatency);
    builder.setSharingMode(SharingMode::Exclusive);
    builder.setFormat(AudioFormat::Float);
    builder.setChannelCount(1);
    builder.setCallback(gMetronome);

    builder.openStream(&gStream);
    gStream->requestStart();

    gMetronome->sampleRate = gStream->getSampleRate();
    gMetronome->setBpm(bpm);
    gMetronome->tickCallback = gTickCallback;
}
```

关键配置:

- `PerformanceMode::LowLatency` — 优先延迟而非省电
- `SharingMode::Exclusive` — 独占音频设备,避免与其他 App 抢资源
- `AudioFormat::Float` — 浮点样本,合成精度高
- `setChannelCount(1)` — 单声道
- `sampleRate` 从实际流中读取,避免硬编码与硬件不匹配

## 4. 节拍触发逻辑 — `onAudioReady`

每个音频 buffer 回调都会驱动节拍推进(`metronome.cpp:60-105`):

```cpp
// 来源: android/app/src/main/cpp/metronome.cpp:60-105 (节选)
DataCallbackResult onAudioReady(AudioStream *stream, void *audioData, int32_t numFrames) override {
    float *out = static_cast<float *>(audioData);
    for (int i = 0; i < numFrames; i++) {
        if (!isPlaying) { *out++ = 0.0f; continue; }

        if (sampleCounter >= samplesPerBeat) {
            sampleCounter -= samplesPerBeat;
            clickRemaining = 200;
            frequency = calculateTickFrequency(beat);

            if (tickCallback) {
                tickCallback(beat % beatsPerBar);
            }
            beat++;
        }

        float sample = 0.0f;
        if (clickRemaining > 0) {
            double t = (double) clickRemaining / sampleRate;
            sample = (float)(
                    0.8 *
                    sin(2.0 * M_PI * frequency * t) *
                    (clickRemaining / 200.0)
            );
            clickRemaining--;
        }

        *out++ = sample;
        sampleCounter++;
    }
    return DataCallbackResult::Continue;
}
```

**核心循环**:
1. 当 `sampleCounter` 累计到 ≥ `samplesPerBeat` 触发一拍
2. 立即调用 Dart 回调 `tickCallback(beat % beatsPerBar)` 通知 UI 节拍序号 (0-based within bar)
3. `clickRemaining = 200` 启动一个 200 sample 的"敲击声"包络
4. 在 200 sample 内用 `sin(2π × freq × t) × 包络衰减` 合成正弦波
5. 包络公式 `(clickRemaining / 200.0)` 实现线性衰减 → 模拟"哒"声的迅速消失

**同步保证**:回调函数(`tickCallback`)与音频 buffer 在同一线程执行,但回调到 Dart 后,Dart 通过 `StreamController.add` 跨 isolate 通知 UI,UI 收到 tick 的时刻有微小延迟,但音频合成已经发生 — 这是 **"音频先发,UI 后到"** 的典型时序解耦模式。

## 5. 重音频率切换

`calculateTickFrequency`(`metronome.cpp:107-113`):

```cpp
// 来源: android/app/src/main/cpp/metronome.cpp:107-113
double calculateTickFrequency(int currentBeat) const {
    if (useAccentTick && (currentBeat % beatsPerBar == 0)) {
        return accentTickFrequency;
    }
    return regularTickFrequency;
}
```

- 重音:1500Hz(高)
- 普通音:1000Hz(低)

调用时机在 `onAudioReady` 内:`metronome.cpp:77` `frequency = calculateTickFrequency(beat)`,该决策影响**当前 tick 的音频**,**紧接着**调 Dart 回调 → UI 可以同步显示重音圆点。

## 6. Play / Pause / Shutdown

```cpp
// 来源: android/app/src/main/cpp/metronome.cpp:50-58
void play() {
    beat = 0;
    sampleCounter = samplesPerBeat;  // 重置 samples,下一拍立即触发
    isPlaying = true;
}

void pause() { isPlaying = false; }
```

`pause_metronome` / `play_metronome` / `shutdown_audio` 是对应的 C 接口(`metronome.cpp:151-173`):

```cpp
void play_metronome() { if (gMetronome) gMetronome->play(); }
void pause_metronome() { if (gMetronome) gMetronome->pause(); }
void shutdown_audio() {
    if (!gStream) return;
    gStream->stop();
    gStream->close();
    delete gMetronome;
    gStream = nullptr;
    gMetronome = nullptr;
}
```

注意 `shutdown_audio` 必须先 `stop` 再 `delete`,避免音频线程访问已释放对象 — RAII/手动析构的常见雷区。

## 7. 关键设计要点总结

| 设计点 | 实现 | 优势 |
|--------|------|------|
| 调度源 | Oboe 音频回调 + sample 计数 | 抖动 < 1 sample (≈ 0.02 ms @ 48kHz) |
| 音频合成 | 数学正弦波 (`sin`) + 线性包络 | 无需打包 mp3/wav 音频资源,体积小 |
| 重音区分 | 不同频率正弦 (1500/1000Hz) | 物理可闻度强,无需多源文件 |
| 跨线程通信 | C 函数指针 → Dart `NativeCallable.listener` | 音频线程无锁推送,Dart isolate 安全接收 |
| 资源管理 | `gMetronome`/`gStream` 全局静态指针 | 多次 init 安全 (`if (gStream) return;`) |

## 8. 源码引用汇总

- `android/app/src/main/cpp/CMakeLists.txt:1-19` — 构建脚本
- `android/app/src/main/cpp/metronome.h:1-16` — C 接口声明
- `android/app/src/main/cpp/metronome.cpp:7-114` — `Metronome` 类实现
- `android/app/src/main/cpp/metronome.cpp:130-199` — C 接口实现
- `lib/ffi.dart:1-63` — Dart FFI 绑定
- `lib/data/metronome_impl.dart:20-37` — 回调注册
- `lib/data/metronome_impl.dart:38-50` — `_onNativeTick` 接收逻辑
