import 'package:flutter/material.dart';
import 'resize_strategy.dart';
import 'overlay_geometry.dart';

/// 底边缘缩放 — 仅改高度
class ResizeBottomStrategy extends ResizeStrategy {
  @override
  bool matches(Offset local, OverlayGeometry geo) => geo.isInBottomEdge(local);

  @override
  Offset resolveDelta(Offset raw) => Offset(0, raw.dy);
}
