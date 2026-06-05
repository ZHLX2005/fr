import 'package:flutter/material.dart';
import 'resize_strategy.dart';
import 'overlay_geometry.dart';

/// 右下角缩放 — 同时改宽高
class ResizeCornerStrategy extends ResizeStrategy {
  @override
  bool matches(Offset local, OverlayGeometry geo) => geo.isInCorner(local);

  @override
  Offset resolveDelta(Offset raw) => raw;
}
