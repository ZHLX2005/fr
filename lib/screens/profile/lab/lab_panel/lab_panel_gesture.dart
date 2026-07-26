// 下拉面板的输入收敛层，详见类文档。

import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';

import '../lab_perf_log.dart';
import 'lab_panel_state_machine.dart';

/// 下拉面板的**输入收敛层**。
///
/// 面板有三条并行的输入路径，原先全都摊在 _LabPageState 里，与动画驱动、
/// 页面 UI 混在一起（这正是"功能嵌套多"的源头）：
///
///   ① Listener 指针流      —— 主内容拖拽的实时位移与抬手速度
///   ② ScrollNotification   —— 网格滚到顶后继续下拉，转成面板拖拽
///   ③ 把手 GestureDetector —— 面板展开后向上拖拽收起
///
/// 这里把"原始输入 → 状态机调用"的转换全部收进来，页面侧只需要：
///   - 把 Listener / NotificationListener / 把手回调接到本类
///   - 实现 [onProgressChanged]（发布进度）与 [onAction]（播动画）
///
/// 速度改用 [VelocityTracker]：原实现按 `DateTime.now()` 的毫秒差手算
/// `dy/dt`，只取相邻两个事件，抬手瞬间的抖动会直接放大成假速度；
/// VelocityTracker 用最小二乘拟合最近一段轨迹，与 Flutter 自带手势的
/// 速度口径一致（阈值 velocityOpen/velocityClose 沿用不变）。
class LabPanelGestureCoordinator {
  LabPanelGestureCoordinator({
    required this.stateMachine,
    required this.onProgressChanged,
    required this.onAction,
    required this.stopAnimation,
    required this.viewportHeight,
    required this.gridScrollController,
  });

  final LabPullPanelStateMachine stateMachine;

  /// 状态机被改动后调用：把进度发布出去（页面侧写 ValueNotifier）
  final VoidCallback onProgressChanged;

  /// 状态机产出动作后调用：页面侧据此播动画
  final ValueChanged<LabPullPanelAction> onAction;

  /// 需要打断进行中的动画时调用。settleToTarget=true 表示"就当它已经播完"。
  final void Function({bool settleToTarget}) stopAnimation;

  /// 当前视口高度（拖拽换算进度用），由页面在 LayoutBuilder 里更新
  final double Function() viewportHeight;

  /// 主内容网格的滚动控制器，用于判断"是否已经滚到顶"
  final ScrollController Function() gridScrollController;

  VelocityTracker? _velocityTracker;
  double _lastVelocityDy = 0.0;

  // ── ① Listener 指针流 ──────────────────────────────────────────

  void handlePointerDown(PointerDownEvent event) {
    // 每个手指单独一个 tracker：跨手指复用会把两条轨迹拟合成一条假速度
    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker!.addPosition(event.timeStamp, event.position);
    _lastVelocityDy = 0.0;
  }

  void handlePointerMove(PointerMoveEvent event) {
    _velocityTracker?.addPosition(event.timeStamp, event.position);

    final height = viewportHeight();
    if (stateMachine.state == LabPullPanelState.draggingMain && height > 0) {
      stateMachine.updateMainDrag(deltaDy: event.delta.dy, fullHeight: height);
      onProgressChanged();
    }
  }

  void handlePointerUp(PointerUpEvent event) {
    _lastVelocityDy = _velocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0.0;
    _velocityTracker = null;

    if (stateMachine.state == LabPullPanelState.draggingMain) {
      onAction(stateMachine.endMainDrag(velocityDy: _lastVelocityDy));
    }
  }

  void handlePointerCancel(PointerCancelEvent event) {
    _velocityTracker = null;
    _lastVelocityDy = 0.0;
    if (stateMachine.state == LabPullPanelState.draggingMain) {
      onAction(stateMachine.endMainDrag(velocityDy: 0.0));
    }
  }

  // ── ② 主内容滚动通知 ───────────────────────────────────────────

  /// 返回 true 表示"这条通知我消费了"，阻止它继续向上冒泡。
  bool handleScrollNotification(ScrollNotification notification) {
    final controller = gridScrollController();
    if (!controller.hasClients) return false;
    if (!stateMachine.mainContentInteractive) return false;

    // 只有停在列表顶端时，继续下拉才意味着"要拉面板"
    final atTop =
        controller.position.extentBefore <= LabPullPanelMetrics.topEpsilon;
    if (!atTop) return false;

    final height = viewportHeight();

    if (notification is ScrollStartNotification) {
      _log('main scroll start');
      stopAnimation(settleToTarget: true);
      stateMachine.beginMainDrag();
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final dy = notification.dragDetails?.delta.dy;
      if (dy != null && dy > 0) {
        stateMachine.updateMainDrag(deltaDy: dy, fullHeight: height);
        _log('main drag update dy=${dy.toStringAsFixed(1)}');
        onProgressChanged();
        return true;
      }
    }

    if (notification is OverscrollNotification) {
      final dy = notification.dragDetails?.delta.dy;
      if (dy != null && dy > 0) {
        stopAnimation(settleToTarget: true);
        stateMachine.beginMainDrag();
        stateMachine.updateMainDrag(deltaDy: dy, fullHeight: height);
        _log('main overscroll dy=${dy.toStringAsFixed(1)}');
        onProgressChanged();
        return true;
      }
    }

    if (notification is ScrollEndNotification &&
        stateMachine.state == LabPullPanelState.draggingMain) {
      _log('main drag end velocity=${_lastVelocityDy.toStringAsFixed(1)}');
      onAction(stateMachine.endMainDrag(velocityDy: _lastVelocityDy));
      return true;
    }

    return false;
  }

  // ── ③ 把手拖拽 ─────────────────────────────────────────────────

  void handleHandleDragStart() {
    stopAnimation(settleToTarget: true);
    stateMachine.beginPanelDrag();
    _log('panel drag start');
    onProgressChanged();
  }

  void handleHandleDragUpdate(double deltaDy) {
    final height = viewportHeight();
    if (height <= 0) return;
    stateMachine.updatePanelDrag(deltaDy: deltaDy, fullHeight: height);
    _log('panel drag update dy=${deltaDy.toStringAsFixed(1)}');
    onProgressChanged();
  }

  void handleHandleDragEnd(double velocityDy) {
    _log('panel drag end velocity=${velocityDy.toStringAsFixed(1)}');
    onAction(stateMachine.endPanelDrag(velocityDy: velocityDy));
  }

  void _log(String message) {
    labPerfLog(
      '$message progress=${stateMachine.progress.toStringAsFixed(3)} '
      'state=${stateMachine.state.name}',
    );
  }
}
