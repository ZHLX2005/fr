---
name: clock-vs-metronome-lifecycle
description: Clock 是数据驱动（startTime + wall-clock），Metronome 是流驱动（Oboe 持续 emit）。生命周期策略不同：Clock 的 timer 只是 UI tick，退出 page 让 Provider 销毁是合理的；Metronome 的 service 必须跨页面活着。设计混用生命周期时读这个 ref。~
---

# Clock vs Metronome — 数据驱动 vs 流驱动 的生命周期差异

## 一句话区别

| 组件 | 状态类型 | 驱动模型 | 退出页面行为 |
|------|---------|---------|--------------|
| Clock | **数据驱动**（startTime + startRemainingSeconds） | wall-clock 减 startTime = 当前剩余 | Provider 可以销毁，timer 可以停，下次进入重算就行 |
| Metronome | **流驱动**（Oboe 持续 emit float 采样） | audio thread 不停 = 一直有声 | Service 必须活着；page 只是按钮面板 |

## Clock 是怎么"算时间"的

```dart
// LabClockProvider._recalculateRunningClocks()
final elapsed = DateTime.now().difference(clock.startTime!).inSeconds;
final newRemaining = clock.startRemainingSeconds - elapsed;
```

**关键**：剩余时间完全靠 wall-clock 时间差，**不需要 timer 也能算对**。所以：
- 退出 ClockDemo → Provider 销毁 → Timer 停 → **但下次进入 page 时**，Provider 重新构造 → `loadClocks()` → `_recalculateRunningClocks()` 一秒钟内重算 → 用户看到正确剩余
- App 切到后台被 Doze 冻结 → timer 不跑 → `didChangeAppLifecycleState.resumed` 时重算 → 正确剩余
- App 被系统杀 → 重启 → 启动时 `loadClocks()` 读 SP 里的 `startTime` → 立刻重算 → 正确剩余

**timer 在 clock 里的真正作用**（不是算时间）：
1. **每秒钟触发 UI rebuild** — 让用户看到秒级倒数动画
2. **每秒钟把 `remainingSeconds` 写回 SP** — 持久化"上次保存时还剩多少"（防止 app 死亡后 SP 没有最新值）
3. **同步桌面 widget** — 每秒 `_syncToWidget()` 让原生 widget 显示跟得上

也就是说 timer 停了，**时钟显示会冻结在一个值**（直到 page 重新进入或 lifecycle 恢复才更新），但**时间本身没有被破坏**。

## Metronome 是怎么"算时间"的

```cpp
// C++ Oboe audio thread
void onAudioReady(AudioStream *stream, void *audioData, int32_t numFrames) {
    // 每 4ms 左右被叫一次
    // 把当前 sampleCounter 写成下一个 beat 的合成音 / 采样 PCM
}
```

**关键**：发声完全靠 audio thread 持续 emit float 采样到 speaker buffer。**Oboe stream 一旦 `stop()` / `close()`，**声就立刻停了。** 没有 "数据驱动" 这条路。

```dart
// Controller dispose 时必须只 pause，不能 shutdown
MetronomeService.instance.pause();  // ✓
MetronomeService.instance.shutdown();  // ✗ 关 stream，再启动要重新 init
```

## 设计含义

### Clock Provider — 可以跟 page 一起销毁

- 进入 page：Provider 构造，timer 启动
- 退出 page：Provider 销毁，timer 停
- 不影响数据的正确性（数据驱动）
- 不影响 Oboe stream（Clock 用 `requestOwnership` 拿所有权，pause 时不主动调 service）

### Metronome Service — 必须跨 page 活着

- 进入 page：UI 调 `service.play()` / `setBpm` / `loadSample`
- 退出 page：UI 调 `service.pause()`，**不** 调 `shutdown()`
- service 本身不持有任何 UI state — 它只是 audio engine

## 常见错误

| 错误想法 | 实际后果 |
|----------|---------|
| "Clock 是数据驱动，所以退出 page 不用管" | **正确** — Provider 销毁没问题 |
| "Metronome 是流驱动，所以退出 page 也别管" | **错误** — 关 stream 再开需要重 init，sample slot 也会清空 |
| "把 clock 的 timer 当主时钟源" | **错误** — timer 只是 UI tick，wall-clock 才是数据源 |
| "把 metronome 的 pause 当 dispose" | **错误** — pause 之后 stream 还在，下次 play 直接出声 |

## 检查清单

设计新功能时问自己：
1. 这个组件的状态是「数据 + 时间差」还是「持续事件流」？
2. 退出 page 时，外部世界（widget、原生层、其它 demo）还需不需要看它？
3. 重新进入 page 能不能从持久化数据重建？

如果是数据驱动 → page lifecycle 自由
如果是流驱动 → 必须抽 service