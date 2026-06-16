// lib/core/surround_game/mode_factory.dart
//
// 触摸控制器工厂 — 通过统一接口产出带 mode-specific 行为的 TouchController。
//
// 每个 mode（local/lanHost/lanClient）有自己的工厂实现，封装
// 模式专属的触摸坐标映射（如 LAN Host 的 y 镜像）。
// Page 通过工厂创建 TouchController，不直接实例化子类。

import 'widgets/touch_controller.dart';

/// 触摸控制器工厂接口
///
/// 调用方不需要知道具体 TouchController 子类，只需调 create()。
abstract interface class TouchControllerFactory {
  TouchController create();
}
