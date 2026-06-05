import 'package:flutter/material.dart';
import 'overlay_geometry.dart';

/// 交互策略抽象接口
abstract class OverlayInteractionStrategy {
  /// 判定指针落点是否属于此交互区域
  bool matches(Offset local, OverlayGeometry geo);

  /// 指针按下时的初始化
  void onStart(OverlayGeometry geo);

  /// 指针移动（delta = 全局指针的累积位移）
  void onMove(OverlayGeometry geo, Offset delta);

  /// 指针释放
  void onEnd();
}
