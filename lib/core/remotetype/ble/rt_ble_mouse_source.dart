// lib/core/remotetype/ble/rt_ble_mouse_source.dart
//
// BLE 鼠标 → RT1 指针事件的翻译层。
//
// ## 这一层做什么、为什么不做什么
//
// 做：
//   · 把 BLE 的高频报告（典型 125Hz / 8ms）合批到 ~30Hz 再发
//     ——与触摸板链路同一个节拍（kRtPadSendTickMs），两侧节奏一致才好调。
//   · 相对位移可加，所以合批**无损**：这一帧的 dx 加上下一帧的 dx
//     和分开发对 PC 完全等价。
//   · 按键做边沿检测（按下 / 抬起），保证 press/release 成对。
//   · 滚轮单位归一化（notch vs WHEEL_DELTA）。
//
// 不做：
//   · **不套触摸板那套 libinput 加速度曲线**（rt_touchpad_engine 的
//     rtPadAccelFactor）。真鼠标有自己的 DPI，再叠一条加速度曲线就是
//     双曲线叠加，手感会飘。这里的灵敏度是一个**线性系数**，
//     由用户按手感调。
//   · **不碰 RT1 协议**。载荷形状与触摸板那条完全一致
//     （{a:move|button|scroll}），mn-rt 侧零改动。

import 'dart:async';

import '../data/rt_constants.dart';
import '../protocol/rt_session.dart';
import 'rt_ble_mouse.dart';
import 'rt_hid_report.dart';

/// 把 [RtBleMouse] 的报告流翻译成 RT1 指针事件，发给 [RtSession]。
class RtBleMouseSource {
  RtBleMouseSource({
    required this.mouse,
    required this.session,
    this.sensitivity = kRtBleMouseSensitivityDefault,
  });

  final RtBleMouse mouse;
  final RtSession session;

  /// 灵敏度系数（线性）。1.0 = 原始计数 1:1 变像素。
  double sensitivity;

  StreamSubscription<RtHidMouseReport>? _sub;
  Timer? _timer;

  double _pendDx = 0;
  double _pendDy = 0;
  int _pendWheel = 0;
  int _pendHWheel = 0;

  /// 上一次看到的按键位掩码，用于边沿检测。
  int _lastButtons = 0;

  /// 统计（探针与排障用）。
  final Map<String, int> stats = <String, int>{
    'reports': 0,
    'movesSent': 0,
    'buttonsSent': 0,
    'scrollsSent': 0,
    'failed': 0,
  };

  /// 开始接收鼠标事件。
  void start() {
    if (_sub != null) return;
    _sub = mouse.reports.listen(_onReport);
    _timer = Timer.periodic(
      const Duration(milliseconds: kRtPadSendTickMs),
      (_) => _flush(),
    );
  }

  /// 停止接收并冲刷挂起的增量。
  ///
  /// 停止时必须把挂着的位移与按下状态发完 —— 否则 PC 侧左键会卡在按下。
  void stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _flushMoves();
    // 兜底：把还按着的键补一个 release
    if (_lastButtons != 0) {
      for (final name in <String>['left', 'right', 'middle']) {
        if (_lastButtons & _buttonMask(name) != 0) {
          unawaited(
            session.syncMouse(<String, dynamic>{
              'a': 'button',
              'button': name,
              'kind': 'release',
            }),
          );
        }
      }
      _lastButtons = 0;
    }
  }

  void _onReport(RtHidMouseReport r) {
    stats['reports'] = (stats['reports'] ?? 0) + 1;

    if (r.dx != 0 || r.dy != 0) {
      _pendDx += r.dx * sensitivity;
      _pendDy += r.dy * sensitivity;
    }

    if (r.wheel != 0) {
      _pendWheel += RtHidWheel.normalize(r.wheel);
    }
    if (r.hWheel != 0) {
      _pendHWheel += RtHidWheel.normalize(r.hWheel);
    }

    // 按键是离散事件：**不等合批**，立刻发，并且先把挂着的位移冲出去 ——
    // 「先到位后点击」的顺序不能乱（PC 端 MousePump 也是这个规矩）。
    if (r.buttons != _lastButtons) {
      _flushMoves();
      _dispatchButtonEdges(_lastButtons, r.buttons);
      _lastButtons = r.buttons;
    }
  }

  /// 按键边沿：按下 → press，抬起 → release。
  ///
  /// 用 press/release 而不是 click —— 真鼠标的按下与抬起之间可以拖拽，
  /// click 会把拖拽吃掉。
  void _dispatchButtonEdges(int from, int to) {
    for (final name in <String>['left', 'right', 'middle']) {
      final int mask = _buttonMask(name);
      final bool was = from & mask != 0;
      final bool now = to & mask != 0;
      if (was == now) continue;
      unawaited(
        session.syncMouse(<String, dynamic>{
          'a': 'button',
          'button': name,
          'kind': now ? 'press' : 'release',
        }),
      );
      stats['buttonsSent'] = (stats['buttonsSent'] ?? 0) + 1;
    }
  }

  int _buttonMask(String name) {
    switch (name) {
      case 'left':
        return RtHidButtons.left;
      case 'right':
        return RtHidButtons.right;
      case 'middle':
        return RtHidButtons.middle;
    }
    return 0;
  }

  void _flush() {
    _flushMoves();
    if (_pendWheel != 0 || _pendHWheel != 0) {
      final int dx = _pendHWheel;
      final int dy = _pendWheel;
      _pendWheel = 0;
      _pendHWheel = 0;
      unawaited(
        session.syncMouse(<String, dynamic>{
          'a': 'scroll',
          'dx': dx,
          'dy': dy,
        }),
      );
      stats['scrollsSent'] = (stats['scrollsSent'] ?? 0) + 1;
    }
  }

  void _flushMoves() {
    final int ix = _pendDx.truncate();
    final int iy = _pendDy.truncate();
    if (ix == 0 && iy == 0) return;
    _pendDx -= ix;
    _pendDy -= iy;
    unawaited(
      session.syncMouse(<String, dynamic>{'a': 'move', 'dx': ix, 'dy': iy}).then((ok) {
        if (ok) {
          stats['movesSent'] = (stats['movesSent'] ?? 0) + 1;
        } else {
          stats['failed'] = (stats['failed'] ?? 0) + 1;
        }
      }),
    );
  }
}
