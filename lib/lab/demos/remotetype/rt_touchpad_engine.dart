// lib/lab/demos/remotetype/rt_touchpad_engine.dart
//
// 触摸板手势引擎（纯逻辑，零 widget / 零 Flutter 依赖，可单测）。
//
// 输入：原始指针事件（down/move/up/cancel，指针 id + 逻辑坐标 + 毫秒时间戳），
// 与 Flutter 的 Listener 解耦——页面层只做事件搬运。
//
// 输出（三类回调，均已加工为「PC 侧语义」）：
//   onMove(dx, dy)            单指滑动 → 指针位移（已乘加速度与灵敏度）
//   onAction(action)          离散动作：左键 / 右键 / 拖拽按下抬起
//   onScroll(dxTicks, dyTicks) 滚轮格数（整数，正 = 下/右，与 enigo 语义一致）
//   onInertia(active)         惯性滚动开始 / 结束（页面层据此驱动 tick 时钟）
//
// 手势判定规则（与笔记本触摸板习惯一致）：
//   单指静置 ≤220ms 抬手          → 左键
//   单指位移超 slop               → 移动指针（慢速精细、快速长距离）
//   按住 ≥320ms 后再移动          → 左键拖拽（press → 移动 → release）
//   双指静置 ≤420ms 抬手          → 右键
//   双指位移超 slop               → 滚轮（内容跟手：指头下滑 = 内容上推 = 滚轮向上）
//   抬手速度超阈值                → 惯性滚动（衰减到停）
//   第三指落下                    → 忽略（手机系统多用手势占用三指，冲突）
//
// 刻意做成无定时器的被动状态机：所有判定只依赖事件自身携带的时间戳，
// 单测不用 fakeAsync 也能精确复现每条时序路径。惯性是唯一例外——它没有
// 真实指针事件可等，由页面层的帧时钟驱动 tick()。

import 'dart:math' as math;

import 'rt_constants.dart';

/// 离散动作。左键拖拽用 press/release 显式成对，页面层保证异常路径补 release。
enum RtPadAction { leftClick, rightClick, leftPress, leftRelease }

typedef RtPadMoveCallback = void Function(double dx, double dy);
typedef RtPadActionCallback = void Function(RtPadAction action);
typedef RtPadScrollCallback = void Function(int dxTicks, int dyTicks);
typedef RtPadInertiaCallback = void Function(bool active);

/// 指针加速度曲线（px/ms → 缩放系数）。
///
/// libinput 风格：慢速压到 0.5 倍（精细点选），快速放到 3 倍（一甩到底），
/// 中段二次缓入——低速端平坦（不会一抖就窜），高速端线性段足够陡。
double rtPadAccelFactor(double speedPxPerMs) {
  const double s0 = 0.12;
  const double s1 = 2.2;
  const double f0 = 0.5;
  const double f1 = 3.0;
  if (speedPxPerMs <= s0) return f0;
  if (speedPxPerMs >= s1) return f1;
  final t = (speedPxPerMs - s0) / (s1 - s0);
  return f0 + (f1 - f0) * t * t;
}

class _PadPointer {
  _PadPointer(this.sx, this.sy, this.t) : x = sx, y = sy;
  double sx, sy; // 起点（tap slop 判定基准）
  double x, y; // 当前位置
  int t; // 落下时间戳
}

enum _PadPhase {
  /// 无手指。
  idle,

  /// 单指落下、尚未定性（点按 / 移动 / 拖拽）。
  onePending,

  /// 单指移动中。
  oneMove,

  /// 左键按住拖拽中。
  drag,

  /// 双指落下、尚未定性（右键 / 滚轮）。
  twoPending,

  /// 双指滚轮中。
  scroll,

  /// 惯性滚动中（所有手指已离开）。
  inertia,

  /// 收尾：滚轮/双指中途抬走一根，剩指不再产生任何动作（防误触）。
  swallow,

  /// 滚轮收尾：已抬走一根，剩指只等抬手做惯性判定（swallow 不带惯性，
  /// 这里带——两根手指的抬起总有先后，惯性不能因为「第一根先走」就丢）。
  scrollEnding,
}

class RtTouchpadEngine {
  RtTouchpadEngine({
    required this.onMove,
    required this.onAction,
    required this.onScroll,
    this.onInertia,
    this.sensitivity = kRtPadSensitivityDefault,
  });

  final RtPadMoveCallback onMove;
  final RtPadActionCallback onAction;
  final RtPadScrollCallback onScroll;
  final RtPadInertiaCallback? onInertia;

  /// 用户灵敏度偏好（乘在加速度系数上）。
  double sensitivity;

  /// 当前状态名（测试探针用——枚举私有，跨库断言名字比导出枚举干净）。
  String get phaseName => _phase.name;

  final Map<int, _PadPointer> _points = {};
  _PadPhase _phase = _PadPhase.idle;

  /// 已向 PC 发出 leftPress 未配对 release——cancel/异常路径必须补发，
  /// 否则 PC 左键卡死（拖拽挂住）。
  bool _dragArmed = false;

  // 双指基准：第二指落下时的质心（twoPending 的 slop 判定基准）。
  double _twoBaseCx = 0;
  double _twoBaseCy = 0;

  // 滚轮：上一帧质心（增量基准）+ 最后一帧位移（惯性方向）。
  double _prevCx = 0;
  double _prevCy = 0;
  double _lastDx = 0;
  double _lastDy = 0;

  // 速度 EMA（px/ms）。deltas/dt 抖动大，先指数平滑再进曲线/惯性判定。
  double _speedEma = 0;
  int _lastMoveTs = 0;

  // 滚轮格数小数累计（攒满一格才发）+ 惯性速度。
  double _accX = 0;
  double _accY = 0;
  double _flingVx = 0;
  double _flingVy = 0;

  // ================= 指针事件入口 =================

  void down(int id, double x, double y, int tMs) {
    // 惯性中的新触摸：立刻接管（清零速度，剩余格数累积继续走完）
    if (_phase == _PadPhase.inertia) _stopInertia();

    // 登记上限 2 指：第三指（及以上）直接忽略——手机系统手势（截屏、
    // 应用切换）普遍占用三指，误触代价远大于收益。
    if (_points.length >= 2) return;
    _points[id] = _PadPointer(x, y, tMs);

    switch (_points.length) {
      case 1:
        _phase = _PadPhase.onePending;
        _speedEma = 0;
        _accX = 0;
        _accY = 0;
        _lastMoveTs = tMs; // 首个 move 事件的 dt 从落下时刻起算，防 1ms 假速度
      case 2:
        // 第二指落下：单指的一切未定性作废。拖拽挂着的先补 release——
        // 两指同按不是任何手势的前缀，拖拽必须立刻收尾防左键卡死。
        if (_dragArmed) {
          _dragArmed = false;
          onAction(RtPadAction.leftRelease);
        }
        _phase = _PadPhase.twoPending;
        _speedEma = 0;
        _accX = 0;
        _accY = 0;
        _lastMoveTs = tMs;
        _twoBaseCx = _centroidX();
        _twoBaseCy = _centroidY();
        _prevCx = _twoBaseCx;
        _prevCy = _twoBaseCy;
        _lastDx = 0;
        _lastDy = 0;
      default:
        break;
    }
  }

  void move(int id, double x, double y, int tMs) {
    final p = _points[id];
    if (p == null) return; // 未登记（第四指起）不响应
    switch (_phase) {
      case _PadPhase.onePending:
        if (_dist(p.sx, p.sy, x, y) <= kRtPadTapSlop) return;
        if (tMs - p.t >= kRtPadDragLongPressMs) {
          // 按住后才动 = 拖拽：先按下再跟随移动
          _phase = _PadPhase.drag;
          _dragArmed = true;
          onAction(RtPadAction.leftPress);
        } else {
          _phase = _PadPhase.oneMove;
        }
        _emitMove(p, x, y, tMs);
      case _PadPhase.oneMove || _PadPhase.drag:
        _emitMove(p, x, y, tMs);
      case _PadPhase.twoPending:
        // 双指未定态没有 _emitMove：位置在这里手动更新，否则质心永远是
        // 落下时的基准点，永远到不了 slop 阈值（滚轮永远触发不了）。
        p.x = x;
        p.y = y;
        final cx = _centroidX();
        final cy = _centroidY();
        if (_dist(_twoBaseCx, _twoBaseCy, cx, cy) > kRtPadTapSlop) {
          _phase = _PadPhase.scroll;
        }
      case _PadPhase.scroll:
        p.x = x;
        p.y = y;
        _emitScroll(tMs);
      case _PadPhase.inertia:
      case _PadPhase.swallow:
      case _PadPhase.scrollEnding:
      case _PadPhase.idle:
        break;
    }
  }

  void up(int id, double x, double y, int tMs) {
    final p = _points.remove(id);
    if (p == null) return;
    switch (_phase) {
      case _PadPhase.onePending:
        final moved = _dist(p.sx, p.sy, x, y) > kRtPadTapSlop;
        final quick = tMs - p.t <= kRtPadTapMaxMs;
        if (!moved && quick) onAction(RtPadAction.leftClick);
        if (_points.isEmpty) _phase = _PadPhase.idle;
      case _PadPhase.oneMove:
        if (_points.isEmpty) _phase = _PadPhase.idle;
      case _PadPhase.drag:
        if (_dragArmed) {
          _dragArmed = false;
          onAction(RtPadAction.leftRelease);
        }
        if (_points.isEmpty) _phase = _PadPhase.idle;
      case _PadPhase.twoPending:
        // 双指都在点按圈内且抬得够快 → 右键；中途抬走一根 → 剩指吞掉
        final quick = tMs - p.t <= kRtPadTwoFingerTapMaxMs;
        if (quick && _points.length == 1) {
          onAction(RtPadAction.rightClick);
          _phase = _PadPhase.swallow;
        } else if (_points.isEmpty) {
          _phase = _PadPhase.idle;
        } else {
          _phase = _PadPhase.swallow;
        }
      case _PadPhase.scroll:
        if (_points.isNotEmpty) {
          _phase = _PadPhase.scrollEnding; // 剩指只等抬手做惯性判定
          break;
        }
        _finishScrollWithInertia();
      case _PadPhase.scrollEnding:
        if (_points.isEmpty) _finishScrollWithInertia();
      case _PadPhase.swallow:
        if (_points.isEmpty) _phase = _PadPhase.idle;
      case _PadPhase.inertia:
      case _PadPhase.idle:
        break;
    }
  }

  /// 滚轮全部抬手：速度够快 → 惯性滚动（方向取最后一帧位移）。
  void _finishScrollWithInertia() {
    final len = _len(_lastDx, _lastDy);
    if (_speedEma >= kRtPadFlingStartPxMs && len > 0) {
      _flingVx = _lastDx / len * _speedEma;
      _flingVy = _lastDy / len * _speedEma;
      _phase = _PadPhase.inertia;
      onInertia?.call(true);
    } else {
      _phase = _PadPhase.idle;
    }
  }

  /// 指针被系统抢走（来电 / 通知栏）：按「全部抬手」处理，
  /// 拖拽挂着时必须补 release，否则 PC 左键卡死。
  void cancelAll() {
    if (_dragArmed) {
      _dragArmed = false;
      onAction(RtPadAction.leftRelease);
    }
    _points.clear();
    _stopInertia();
    _phase = _PadPhase.idle;
  }

  /// 惯性滚动的时钟驱动（页面层 Ticker 每帧调用，dtMs = 距上次帧的毫秒）。
  /// 衰减到阈值以下自动结束并发 onInertia(false)。
  void tick(int dtMs) {
    if (_phase != _PadPhase.inertia || dtMs <= 0) return;
    final decay =
        math.pow(kRtPadFlingDecayPer16Ms, dtMs / 16.0).toDouble();
    _flingVx *= decay;
    _flingVy *= decay;
    // 惯性沿用「内容跟手」符号：速度方向就是内容方向，滚轮取反
    _accX += -_flingVx * dtMs / kRtPadScrollPxPerTick;
    _accY += -_flingVy * dtMs / kRtPadScrollPxPerTick;
    _emitAccumulatedTicks();
    if (_flingVx * _flingVx + _flingVy * _flingVy <
        kRtPadFlingStopPxMs * kRtPadFlingStopPxMs) {
      _stopInertia();
      _phase = _PadPhase.idle;
    }
  }

  // ================= 内部 =================

  void _emitMove(_PadPointer p, double x, double y, int tMs) {
    final dx = x - p.x;
    final dy = y - p.y;
    p.x = x;
    p.y = y;
    final dt = (tMs - _lastMoveTs).clamp(1, 200);
    _lastMoveTs = tMs;
    final speed = _len(dx, dy) / dt;
    _speedEma += (speed - _speedEma) * 0.35;
    final factor = rtPadAccelFactor(_speedEma) * sensitivity;
    if (dx != 0 || dy != 0) onMove(dx * factor, dy * factor);
  }

  void _emitScroll(int tMs) {
    final cx = _centroidX();
    final cy = _centroidY();
    final dx = cx - _prevCx;
    final dy = cy - _prevCy;
    _prevCx = cx;
    _prevCy = cy;
    if (dx == 0 && dy == 0) return;
    _lastDx = dx;
    _lastDy = dy;
    final dt = (tMs - _lastMoveTs).clamp(1, 200);
    _lastMoveTs = tMs;
    final speed = _len(dx, dy) / dt;
    _speedEma += (speed - _speedEma) * 0.3;
    // 内容跟手：指头下移（dy>0）→ 内容上推 → 滚轮向上（负）
    _accX += -dx / kRtPadScrollPxPerTick;
    _accY += -dy / kRtPadScrollPxPerTick;
    _emitAccumulatedTicks();
  }

  void _emitAccumulatedTicks() {
    final ix = _accX.truncate();
    final iy = _accY.truncate();
    if (ix == 0 && iy == 0) return;
    _accX -= ix;
    _accY -= iy;
    onScroll(ix, iy);
  }

  void _stopInertia() {
    final wasActive = _phase == _PadPhase.inertia;
    _flingVx = 0;
    _flingVy = 0;
    // 只在真的停掉一段惯性时才通知——空闲态的 cancelAll 不该凭空发 false
    if (wasActive) onInertia?.call(false);
  }

  double _centroidX() {
    var s = 0.0;
    for (final p in _points.values) {
      s += p.x;
    }
    return s / _points.length;
  }

  double _centroidY() {
    var s = 0.0;
    for (final p in _points.values) {
      s += p.y;
    }
    return s / _points.length;
  }
}

double _dist(double x1, double y1, double x2, double y2) =>
    _len(x2 - x1, y2 - y1);

double _len(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
