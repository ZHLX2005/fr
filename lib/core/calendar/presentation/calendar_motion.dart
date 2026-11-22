/// 日历模块动效基建：弹簧吸附、动量投射、指数阻力、平滑曲线。
///
/// 参数族移植自 docs/prototypes/calendar-capsule-nav.html（与
/// lib/lab/demos/notification_pull 同源的 SpringSimulation 参数）。
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// 跟手吸附弹簧（月历收展）。
const SpringDescription kCalendarCollapseSpring = SpringDescription(
  mass: 1,
  stiffness: 205,
  damping: 29,
);

/// 胶囊页签弹簧。原 300/22（≈230ms、带回弹）手感过急；改用面板滑行的
/// 170/26（近临界阻尼）——过渡拉长且收尾柔和，五页签联动更顺。
const SpringDescription kCalendarTabSpring = SpringDescription(
  mass: 1,
  stiffness: 170,
  damping: 26,
);

/// 面板内容惯性滑行弹簧（原型 makeKinetic 同参 k170/c26）。
const SpringDescription kCalendarPanelSpring = SpringDescription(
  mass: 1,
  stiffness: 170,
  damping: 26,
);

/// 月历 / 周条翻页轮盘弹簧。
const SpringDescription kCalendarFlipSpring = SpringDescription(
  mass: 1,
  stiffness: 300,
  damping: 28,
);

/// 松手前动量投射时长（ms）。
const int kCalendarMomentumMs = 130;

/// 指针死区（px）。
const double kCalendarDragDeadZone = 4;

/// 月历行高（收起态单周行 / 展开态每行统一高度）。
const double kCalendarRowHeight = 56;

double calendarClamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// C² 连续平滑曲线（收起时非选中行的渐隐）。
double calendarSmootherstep(double t) {
  final x = calendarClamp01(t);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

/// 收起端的指数阻力（通知栏 demo 同款）。
double calendarRubber(double x) => 62 * (1 - math.exp(-x / 130));

/// 列表边缘阻力：随视口高度放大（原型 makeKinetic 的 rubberWK）。
double calendarRubberView(double x, double viewport) =>
    viewport * (1 - 1 / (x * 0.55 / math.max(1.0, viewport) + 1));

/// 动量投射：按松手速度 [velocityPxPerMs] 投射 130ms 后的值。
double calendarProject(double value, double velocityPxPerMs, double range) =>
    value + velocityPxPerMs * kCalendarMomentumMs / math.max(1.0, range);

/// 弹簧驱动器：AnimationController.unbounded + SpringSimulation。
///
/// 所有状态变化都通过 [onUpdate] 回调（内含 ValueNotifier 时即逐帧通知）。
class CalendarSpring {
  CalendarSpring({
    required TickerProvider vsync,
    required this.description,
    VoidCallback? onUpdate,
  }) {
    _controller = AnimationController.unbounded(vsync: vsync);
    if (onUpdate != null) {
      _controller.addListener(onUpdate);
    }
  }

  final SpringDescription description;
  late final AnimationController _controller;

  /// 最近一次 [to] 的目标值。用于 onTick 分支判断当前弹簧的意图方向：
  /// 从 0 起步 to(1) 的首个 tick 上报 value=0（elapsed=0），若回弹分支
  /// 只看 value≤0.001 会误杀动画（此为既有 StackOverflow 的根因）。
  double? _lastToTarget;

  double get value => _controller.value;

  /// 当前速度（单位/秒，与 AnimationController.velocity 一致）。
  /// 胶囊 pill 的高速拉伸按原型 stretch=min(0.14,|v|*0.012) 由此驱动。
  double get velocity => _controller.velocity;

  bool get isAnimating => _controller.isAnimating;

  /// 最近一次 [to] 的目标；从未调用过时视为 1（朝目标吸附）。
  double get lastToTarget => _lastToTarget ?? 1;

  void jump(double value) {
    _controller.stop();
    // 同值短路：onUpdate 回调（_onTick）里常出现 jump(0) 复位，若不
    // 短路，value= 会同步 notifyListeners 重入 _onTick 造成无限递归
    // （StackOverflow）。值未变化时跳过通知即可斩断重入链。
    if (_controller.value == value) return;
    _controller.value = value;
  }

  /// 以初速度 [velocity]（单位与 value 一致）向 [target] 吸附。
  void to(double target, {double velocity = 0}) {
    _lastToTarget = target;
    _controller.animateWith(
      SpringSimulation(description, _controller.value, target, velocity),
    );
  }

  void stop() => _controller.stop();

  void dispose() => _controller.dispose();
}

/// 指针速度采样（8 帧窗口，px/ms）。
class CalendarVelocitySampler {
  final List<double> _times = [];
  final List<double> _positions = [];

  void reset(double position) {
    _times
      ..clear()
      ..add(_nowMs());
    _positions..clear()..add(position);
  }

  void add(double position) {
    _times.add(_nowMs());
    _positions.add(position);
    if (_times.length > 8) {
      _times.removeAt(0);
      _positions.removeAt(0);
    }
  }

  /// px/ms；样本不足或时间跨度过短时返回 0。
  double pxPerMs() {
    if (_times.length < 2) return 0;
    final dt = _times.last - _times.first;
    if (dt < 10) return 0;
    return (_positions.last - _positions.first) / dt;
  }

  static double _nowMs() =>
      DateTime.now().microsecondsSinceEpoch / 1000.0;
}
