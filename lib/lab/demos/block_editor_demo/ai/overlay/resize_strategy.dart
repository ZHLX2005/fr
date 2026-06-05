import 'package:flutter/material.dart';
import 'interaction.dart';
import 'overlay_geometry.dart';

/// 缩放策略基类 — 子类只需覆写 [resolveDelta] 决定哪些轴生效
abstract class ResizeStrategy extends OverlayInteractionStrategy {
  Size? _sizeAnchor;

  @override
  void onStart(OverlayGeometry geo) {
    _sizeAnchor = geo.size;
  }

  /// 子类覆写此方法，返回实际要应用的 delta
  Offset resolveDelta(Offset rawDelta);

  @override
  void onMove(OverlayGeometry geo, Offset rawDelta) {
    if (_sizeAnchor == null) return;
    final delta = resolveDelta(rawDelta);
    geo.size = geo.clampSize(Size(
      _sizeAnchor!.width + delta.dx,
      _sizeAnchor!.height + delta.dy,
    ));
  }

  @override
  void onEnd() {
    _sizeAnchor = null;
  }
}
