// lib/core/surround_game/local/widgets/touch_controller_factory.dart
//
// Local 模式触摸控制器工厂 — 使用共享基类，不镜像触摸坐标。

import '../../mode_factory.dart';
import '../../widgets/touch_controller.dart';

/// Local 模式工厂 — 产出标准的 TouchController（不镜像坐标）
class LocalTouchControllerFactory implements TouchControllerFactory {
  const LocalTouchControllerFactory();

  @override
  TouchController create() => TouchController();
}
