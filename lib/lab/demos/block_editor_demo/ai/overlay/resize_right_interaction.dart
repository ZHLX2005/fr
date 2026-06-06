import 'package:flutter/material.dart';
import 'resize_strategy.dart';
import 'overlay_geometry.dart';

/// 右边缘缩放 — 仅改宽度
class ResizeRightStrategy extends ResizeStrategy {
  @override
  bool matches(Offset local, OverlayGeometry geo) => geo.isInRightEdge(local);

  @override
  Offset resolveDelta(Offset raw) => Offset(raw.dx, 0);
}
