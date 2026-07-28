---
name: oboe-cpp-synthesis
description: C++ Oboe AudioStreamCallback 的工作原理 — 什么是 PCM sample、缓冲机制、sampleCounter 与时间的关系、实时 sin 合成的数学细节。读主 SKILL.md 之后、对 Oboe 内部不熟时加载。
---

# C++ Oboe 实时 sin 合成原理

## 1. 音频流的物理模型

**PCM（脉冲编码调制）= 一串数字化的"声音气压快照"**：

```
时间 →  ┌──┐  ┌──┐ ┌────┐  ┌────┐ ┌──┐  ┌──┐
样本 →  │  │  │  │ │    │  │    │ │  │  │  │
        ↑每次采样 = 一帧 = 1 个 float
        sampleRate = 每秒采样次数 (48000 Hz = 一秒 48000 个样本)
```

| 概念 | 数值含义 |
|------|----------|
| **sampleRate** | 每秒采样点数（Oboe 默认 48000 Hz） |
| **numFrames** | 一次回调要产出的样本数（Android 上常见 192~1024） |
| **period** | 回调间隔 = `numFrames / sampleRate` 秒（192/48000 = 4ms） |
| **sampleCounter** | 当前已合成到第几个样本（单调递增） |

**延迟公式**：理论延迟 = 回调周期 + 系统缓冲。比如 numFrames=192, sampleRate=48000 → 回调 4ms 一次，开 2 个缓冲 → 理论延迟 8ms。

## 2. AudioStreamCallback 工作流

Oboe 是**回调式**音频 API：系统音频线程不断从 C++ 类拉数据。

```cpp
class Metronome : public AudioStreamCallback {
public:
    DataCallbackResult onAudioReady(
        AudioStream *stream,       // 当前音频流指针（用来查 sampleRate 等）
        void *audioData,           // 你要写入的 PCM 缓冲区
        int32_t numFrames          // 本次要填多少帧
    ) override {
        float *out = static_cast<float *>(audioData);
        for (int i = 0; i < numFrames; i++) {
            // ... 在这里算每个 sample 的浮点值
            *out++ = sample;
        }
        return DataCallbackResult::Continue;  // 继续送下一批
    }
};
```

**关键事实**：
- `onAudioReady` 在 **Android 系统的 AAudio/Oboe 音频线程**调用，**不是 Dart isolate**
- 每 4ms 被系统拉一次，必须在这段时间内填满 buffer，否则会 underrun（爆音/卡顿）
- 一次写一帧（per-sample loop），不能累积太久
- 返回 `Continue` 让系统继续喂数据；返回 `Stop` 会停流

## 3. 实时 sin 合成数学

**最基础的形式**：

```cpp
float sample = amplitude * sin(2 * M_PI * frequency * t);
```

其中 `t` 是**当前 sample 的时间**（秒）：

```cpp
double t = sampleCounter / sampleRate;  // 累积时间（从 0 开始）
```

**问题**：浮点 `t` 累积久了会精度漂移（跑 10 分钟后 sin 的相位会偏几个 sample）。

**正确做法**：用 **相位累加器** 而不是累积时间：

```cpp
double phase = 0.0;
double phaseIncrement = frequency * 2 * M_PI / sampleRate;  // 每帧相位增量

for (int i = 0; i < numFrames; i++) {
    float sample = amplitude * sin(phase);
    phase += phaseIncrement;
    if (phase > 2 * M_PI) phase -= 2 * M_PI;  // 防止溢出
}
```

## 4. 节拍器里的关键状态机

**两个独立的"计数器"在 audio callback 里协同**：

```cpp
double sampleCounter = 0;       // 跑了多少个 sample
double samplesPerBeat = 0;      // 一拍占多少 sample

void updateTiming() {
    samplesPerBeat = sampleRate * 60.0 / bpm;  // 例 bpm=120 → 48000*60/120 = 24000
}

void onAudioReady(...) {
    for (int i = 0; i < numFrames; i++) {
        if (!isPlaying) { *out++ = 0; continue; }

        // 一拍到了
        if (sampleCounter >= samplesPerBeat) {
            sampleCounter -= samplesPerBeat;  // 不直接清零，保留余数（相位锁）
            // 触发 click：开始 fill clickRemaining 个 sample 的正弦包络
            clickRemaining = 200;
            frequency = ...;
            tickCallback(beatIndex);  // ← 关键：通知 Dart
            beat++;
        }

        // 填当前 sample
        float sample = 0;
        if (clickRemaining > 0) {
            // 衰减包络
            sample = amplitude * sin(2 * M_PI * frequency * t)
                     * (clickRemaining / 200.0);
            clickRemaining--;
        }

        *out++ = sample;
        sampleCounter++;
    }
}
```

**为什么 `sampleCounter -= samplesPerBeat` 而不是 `= 0`？**

因为 `samplesPerBeat` 不一定整除回调周期。比如 bpm=120 时 samplesPerBeat=24000，但回调周期是 192（4ms）。一次回调结束时 sampleCounter 可能 = 192，过了 120 次回调才到 24000。如果直接清零，**相位会漂移 192 个 sample**。

**余数法**：`sampleCounter -= samplesPerBeat` 永远保留 0~192 之间的余数，下一拍开始的位置精确到 sample 级。

## 5. 强度音色差异化的物理原理

| 维度 | 人耳感知原理 |
|------|--------------|
| **频率** | 1000~2000 Hz 是听觉最敏感区间；700 Hz 显得闷，2200 Hz 显得刺耳 |
| **振幅** | 1.0 / 0.7 / 0.4 听感差距约 2.5 倍/3 倍/1.7 倍 |
| **时长** | 200 sample ≈ 4ms 听感"啪"；300 sample ≈ 6ms 听感"咚"（更长更浑厚） |
| **谐波** | 基频 + 2x + 3x 形成"复合音"，比纯基频更"亮" |

**单维差异不够**：
- 只改频率：1000Hz → 1500Hz 听感差约 1.5 倍
- 只改振幅：0.4 → 1.0 差距约 2.5 倍，但仍像同一件乐器
- 4 维同步拉开 → 真的像"两种不同鼓的敲击"

## 6. 衰减包络数学

```cpp
// 指数衰减（典型打击乐包络）
float envelope = exp(-t * 80);  // t 从 0 到 ~0.06s

// 线性衰减（节拍器典型）
float env = clickRemaining / (float)clickSamples;  // 1 → 0 线性
```

**为什么是衰减？** 打击乐（鼓、响板）的物理特性是"敲击瞬间最强，~5-10ms 内衰减完"，所以包络必须从高到低。如果用恒定振幅，听上去像"嗡嗡声"不是"敲击声"。

## 7. 钳位与溢出

```cpp
if (sample > 1.0f) sample = 1.0f;
else if (sample < -1.0f) sample = -1.0f;
```

**为什么必要**：基频 + 2x 谐波 + 3x 谐波叠加后峰值 = `amplitude * (1 + 0.4 + 0.2) = amplitude * 1.6`。如果 amplitude=1.0，叠加峰值为 1.6 → **削顶失真**（听起来像破音）。要么降振幅，要么钳位，要么归一化。

## 8. PerformanceMode 与 SharingMode

```cpp
builder.setPerformanceMode(PerformanceMode::LowLatency);   // 低延迟路径
builder.setSharingMode(SharingMode::Exclusive);              // 独占设备
```

| Mode | 含义 | 用法 |
|------|------|------|
| `LowLatency` | 走 MMAP/AAudio Fast Path | 实时交互（节拍器、游戏） |
| `None` | 默认 | 普通音乐播放 |
| `PowerSaving` | 走 AAudio Legacy | 后台音乐 |

| Sharing | 含义 |
|---------|------|
| `Exclusive` | 独占音频硬件，最短路径（其它 app 静音） |
| `Shared` | 与其它 app 共享音频设备 |

节拍器必须用 `Exclusive + LowLatency`。

## 9. 调试工具

```cpp
// 打印实际生效的 sample rate（不同设备可能不同）
gMetronome->sampleRate = gStream->getSampleRate();
gMetronome->setBpm(bpm);

// 打印 callback 被调用的频率
int callCount = 0;
DataCallbackResult onAudioReady(...) override {
    callCount++;
    if (callCount % 100 == 0) {
        LOGD("callback #%d, sampleRate=%f", callCount, sampleRate);
    }
    // ...
}
```

Android Logcat 过滤 `tag:oboe` 或你自定义 tag。

## 10. 关键陷阱清单

| 陷阱 | 现象 | 修法 |
|------|------|------|
| `t = sampleCounter / sampleRate` 累积 | 长跑后 sin 相位漂 | 用 `phase += phaseIncrement` |
| `sampleCounter = 0` 直接清零 | 一拍位置精确度差 ±numFrames | `sampleCounter -= samplesPerBeat` 保留余数 |
| `samplesPerBeat = (60.0 / bpm) * sampleRate` 整除 | bpm 非整数拍时长有误差 | 用 double 不用 int |
| callback 里做 `new` / 分配内存 | GC 抖动 / 系统 underrun | 预分配所有 buffer |
| callback 里打印 logcat | logcat IO 阻塞 | 节流（每 100 帧打一次） |
| callback 里调 Dart 代码没线程切换 | ANR 或 crash | 必须 `NativeCallable.listener` 异步派发 |
| 振幅叠加后不钳位 | 削顶失真 | 钳位到 [-1, 1] |