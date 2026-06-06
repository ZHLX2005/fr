import 'package:flutter/material.dart';
import 'overlay_geometry.dart';
import 'overlay_state.dart';
import 'interaction.dart';
import 'drag_interaction.dart';
import 'resize_right_interaction.dart';
import 'resize_bottom_interaction.dart';
import 'resize_corner_interaction.dart';

/// 统一交互调度器 — 管理拖拽 + 三种缩放，widget 层只需调三个方法
class OverlayManager extends ChangeNotifier {
  final OverlayGeometry geo;

  OverlayInteractionStrategy? _active;
  final List<OverlayInteractionStrategy> _strategies;
  Offset? _globalAnchor;

  OverlayManager({required this.geo})
      : _strategies = [
          ResizeCornerStrategy(),
          ResizeRightStrategy(),
          ResizeBottomStrategy(),
          DragStrategy(),
        ];

  /// 当前激活的交互类型
  OverlayInteraction get activeInteraction {
    if (_active == null) return OverlayInteraction.none;
    return _active is DragStrategy
        ? OverlayInteraction.drag
        : _active is ResizeCornerStrategy
            ? OverlayInteraction.resizeCorner
            : _active is ResizeRightStrategy
                ? OverlayInteraction.resizeRight
                : _active is ResizeBottomStrategy
                    ? OverlayInteraction.resizeBottom
                    : OverlayInteraction.none;
  }

  /// 指针按下 — 遍历策略列表，锁定匹配的第一个
  void handlePointerDown(Offset local, Offset global) {
    if (_active != null) return;
    for (final s in _strategies) {
      if (s.matches(local, geo)) {
        _active = s;
        _globalAnchor = global;
        s.onStart(geo);
        notifyListeners();
        return;
      }
    }
  }

  /// 指针移动 — 委派给已锁定的策略
  void handlePointerMove(Offset global) {
    if (_active == null || _globalAnchor == null) return;
    final delta = global - _globalAnchor!;
    _active!.onMove(geo, delta);
    notifyListeners();
  }

  /// 指针释放 — 解锁
  void handlePointerUp() {
    _active?.onEnd();
    _active = null;
    _globalAnchor = null;
  }
}
