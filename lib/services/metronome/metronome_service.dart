// lib/services/metronome/metronome_service.dart
//
// 公共入口 —— 条件 re-export：native (Android/iOS) 走 io 实现（dart:ffi +
// libmetronome.so），web 走 stub 实现（无 ffi，所有方法安全 no-op）。
//
// 这样 main.dart / LabClockProvider / beat_coordinator 等无条件 import 此文件
// 的代码在 web 平台也能编译通过；行为层面 web 上 metronome 不响（无音频）。

export 'metronome_service_io.dart'
    if (dart.library.js_interop) 'metronome_service_web.dart';
