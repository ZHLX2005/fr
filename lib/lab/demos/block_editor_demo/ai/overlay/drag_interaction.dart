import 'package:flutter/material.dart';
import 'interaction.dart';
import 'overlay_geometry.dart';

/// 拖拽策略 — 通过 header 区域拖动窗口
class DragStrategy extends OverlayInteractionStrategy {
  Offset? _positionAnchor;

  @override
  bool matches(Offset local, OverlayGeometry geo) => geo.isInHeader(local);

  @override
  void onStart(OverlayGeometry geo) {
    _positionAnchor = geo.position;
  }

  @override
  void onMove(OverlayGeometry geo, Offset delta) {
    if (_positionAnchor == null) return;
    geo.position = _positionAnchor! + delta;
  }

  @override
  void onEnd() {
    _positionAnchor = null;
  }
}
