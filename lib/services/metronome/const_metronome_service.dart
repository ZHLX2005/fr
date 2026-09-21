// lib/services/metronome/const_metronome_service.dart
//
// [MetronomeService] 的生命周期常量。
//
// 刻意放在 services/ 而不是 lab/demos/metronome/const_metronome.dart ——
// 后者是 demo 层的 UI 常量（BPM 范围、预设拍号），services 层不应反向依赖 lab。

/// 停止播放后，Oboe 流保持打开多久再自动关闭。
///
/// 背景：Oboe 流是 LowLatency + Exclusive 的输出流，`init_audio()` 里
/// `requestStart()` 之后回调会一直跑（即使 `pause()` 了也只是输出静音），
/// 音频 HAL 常驻会阻止 CPU 进入深度睡眠 —— 这是被系统判定「后台高耗电」的
/// 主要原因之一。所以空闲一段时间后必须真正 `shutdown()` 掉。
///
/// 取 30s 的理由：既覆盖「暂停一下马上继续」（不会重开流引入延迟），
/// 又保证用户真的离开后不会长时间占着音频设备。重开一次流的代价约
/// 10~50ms，对用户主动触发的播放无感。
const Duration kMetronomeIdleShutdownDelay = Duration(seconds: 30);

/// accent 档位数量（0=弱, 1=次强, 2=强），与 cpp 端 `gSlots[3]` 对齐。
const int kMetronomeSampleLevels = 3;
