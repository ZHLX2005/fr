---
name: Ha04-Oboe实时合成原理
description: Oboe 实时合成的原理背景指针页。写或调 C++ Oboe 合成代码、对 PCM/回调/相位累加器/包络数学不熟时先看 30 秒模型，全文教程在 docs/architecture/。
---

# Ha04 — Oboe 实时合成原理（指针页）

> **何时读**：写或调 C++ Oboe 合成代码，需要理解 PCM、sampleCounter、回调时序、相位累加器或包络数学时。本页只留 30 秒模型与指针——原理教程全文在 `docs/architecture/oboe-realtime-synthesis.md`（教程叙述不进 `references/`）；实操 SOP 在 [[Ha01-Oboe音频桥接SOP]] 与 [[Ha03-Clock与Metronome生命周期]]。

## 30 秒模型

| 概念 | 一句话 |
|---|---|
| PCM / 回调 | `onAudioReady` 在系统 AAudio/Oboe 音频线程每 period（numFrames/sampleRate，约 4ms）拉一次，必须在周期内填满 buffer，否则 underrun（爆音/卡顿） |
| 相位累加器 | `phase += frequency*2π/sampleRate` 并回绕——不要累积时间 `t`（浮点漂移，长跑后 sin 相位偏移） |
| 拍位置 | `sampleCounter -= samplesPerBeat` 保留余数（相位锁）；直接 `= 0` 会差 ±numFrames 个 sample |
| 包络 | 敲击声必须衰减包络（线性 `clickRemaining/clickSamples` 或指数 `exp(-t*80)`）；恒定振幅听起来是嗡嗡声 |
| 强弱差异 | 频率/振幅/时长/谐波 4 维同步拉开才是「两种鼓」；单维调整听感不够 |
| 钳位 | 基频+谐波叠加峰值可达 amplitude×1.6，必须钳位到 [-1, 1] 防削顶失真 |
| PerformanceMode | 节拍器必须 `Exclusive + LowLatency`（MMMAP/AAudio Fast Path） |

公式、状态机代码与推导细节见 `docs/architecture/oboe-realtime-synthesis.md` 第 1–10 节（第 10 节是关键陷阱清单：累积时间漂移、清零丢余数、callback 内分配内存/logcat/跨线程调 Dart 等）。

## 验证出口

- 本页是原理指针页，无可执行验证；合成改动的验证走 [[Ha01-Oboe音频桥接SOP]] 的验证节与 [[H00-音频路由]] 端到端动线收尾（原生改动过 build apk）。
