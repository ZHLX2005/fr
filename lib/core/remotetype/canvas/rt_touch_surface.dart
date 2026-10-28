// lib/core/remotetype/canvas/rt_touch_surface.dart
//
// 触摸手势面（自包含）：Listener → 引擎 → 合批发送 → 惯性帧钟 + 动作反馈。
// 手势判定全在 rt_touchpad_engine（纯逻辑），本文件只做搬运：
//   Listener 指针事件 → engine.down/move/up/cancel
//   engine 回调 → 合批（kRtPadSendTickMs）→ session.syncMouse
//
// [RtTouchSurface] 是手势的唯一接线处，横屏画布（rt_canvas_view）的触摸板
// 模块直接嵌它。连接点 / 圆形小钮 / 灵敏度 sheet 一并公开共用。
// （原全屏触摸板页 RtTouchpadView 已退役——能力被画布的触摸板模块覆盖。）
//
// 断连不拦手势：本地照常判定，仅在发送处静默丢弃并低频提示（回连自愈）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import '../data/rt_constants.dart';
import '../protocol/rt_session.dart';
import '../protocol/rt_touchpad_engine.dart';

/// 触摸手势面（自包含）。新增手势宿主（画布模块等）直接嵌它。
class RtTouchSurface extends StatefulWidget {
  const RtTouchSurface({
    super.key,
    required this.session,
    required this.connected,
    required this.sensitivity,
    required this.onNotify,
    this.showLegend = true,
    this.showCenterMark = true,
  });

  final RtSession? session;
  final bool connected;
  final double sensitivity;
  final void Function(String message) onNotify;

  /// 首次进入显示手势图例（首次触摸即隐藏）。
  final bool showLegend;

  /// 中心方位标记（「不用看」时的一点方位感）。
  final bool showCenterMark;

  @override
  State<RtTouchSurface> createState() => _RtTouchSurfaceState();
}

class _RtTouchSurfaceState extends State<RtTouchSurface>
    with SingleTickerProviderStateMixin {
  late final RtTouchpadEngine _engine = RtTouchpadEngine(
    onMove: _onMove,
    onAction: _onAction,
    onScroll: _onScroll,
    onInertia: _onInertia,
    sensitivity: widget.sensitivity,
  );

  // 合批发送：增量攒着，定时器到期一次性发（≈33Hz，见 kRtPadSendTickMs）。
  double _pendDx = 0;
  double _pendDy = 0;
  int _pendScrollX = 0;
  int _pendScrollY = 0;
  Timer? _sendTimer;
  bool _sending = false;

  // 惯性滚动的帧时钟。
  Ticker? _inertiaTicker;
  Duration? _lastTickElapsed;

  // 提示层状态。
  late bool _showHint = widget.showLegend;
  String? _actionLabel;
  Timer? _actionTimer;
  DateTime _lastOfflineNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScrollFlashAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(covariant RtTouchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _engine.sensitivity = widget.sensitivity;
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _actionTimer?.cancel();
    _inertiaTicker?.stop();
    _inertiaTicker?.dispose();
    _inertiaTicker = null;
    // 页面退出兜底：拖拽挂着必须补 release，否则 PC 左键卡死。
    // cancelAll 的回调可能触发 _flashAction（setState）——flush 放最后，
    // mounted 守卫兜住 dispose 期间的 UI 触碰。
    _engine.cancelAll();
    unawaited(_flushNow());
    super.dispose();
  }

  // ================= 指针 → 引擎 =================

  void _onPointerDown(PointerDownEvent e) {
    if (_showHint) setState(() => _showHint = false);
    _engine.down(
      e.pointer,
      e.localPosition.dx,
      e.localPosition.dy,
      e.timeStamp.inMilliseconds,
    );
  }

  void _onPointerMove(PointerMoveEvent e) {
    _engine.move(
      e.pointer,
      e.localPosition.dx,
      e.localPosition.dy,
      e.timeStamp.inMilliseconds,
    );
  }

  void _onPointerUp(PointerUpEvent e) {
    _engine.up(
      e.pointer,
      e.localPosition.dx,
      e.localPosition.dy,
      e.timeStamp.inMilliseconds,
    );
  }

  void _onPointerCancel(PointerCancelEvent e) {
    // 系统抢指针（来电/通知栏）：整个引擎按全部抬手收尾
    _engine.cancelAll();
  }

  // ================= 引擎回调 → 发送 =================

  void _onMove(double dx, double dy) {
    _pendDx += dx;
    _pendDy += dy;
    _ensureSendTimer();
  }

  void _onScroll(int dxTicks, int dyTicks) {
    _pendScrollX += dxTicks;
    _pendScrollY += dyTicks;
    _flashScroll();
    _ensureSendTimer();
  }

  void _onAction(RtPadAction action) {
    switch (action) {
      case RtPadAction.leftClick:
        unawaited(HapticFeedback.lightImpact());
        _flashAction('左键');
        _queueFrame({'a': 'button', 'button': 'left', 'kind': 'click'});
      case RtPadAction.rightClick:
        unawaited(HapticFeedback.mediumImpact());
        _flashAction('右键');
        _queueFrame({'a': 'button', 'button': 'right', 'kind': 'click'});
      case RtPadAction.leftPress:
        unawaited(HapticFeedback.selectionClick());
        _flashAction('拖拽');
        _queueFrame({'a': 'button', 'button': 'left', 'kind': 'press'});
      case RtPadAction.leftRelease:
        _queueFrame({'a': 'button', 'button': 'left', 'kind': 'release'});
    }
  }

  void _onInertia(bool active) {
    if (active) {
      _lastTickElapsed = null;
      _inertiaTicker ??= createTicker(_onTick)..start();
    } else {
      _inertiaTicker?.stop();
      _inertiaTicker?.dispose();
      _inertiaTicker = null;
    }
  }

  void _onTick(Duration elapsed) {
    final last = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    if (last == null) return;
    _engine.tick((elapsed - last).inMilliseconds);
  }

  /// 点击类事件不等合批窗口：同帧内直接发出（点按延迟 = 全链路延迟）。
  /// 移动/滚动增量仍走 [_ensureSendTimer] 的合批（顺序由 ws FIFO 保证）。
  void _queueFrame(Map<String, dynamic> mouse) {
    _pendFrameCommands.add(mouse);
    _ensureSendTimer(flushOnly: true);
  }

  final List<Map<String, dynamic>> _pendFrameCommands = [];

  void _ensureSendTimer({bool flushOnly = false}) {
    if (_sendTimer != null) return;
    // flushOnly：点击/快捷键要立即出站，但同一拍里攒的移动增量一并带走。
    _sendTimer = Timer(
      Duration(milliseconds: flushOnly ? 0 : kRtPadSendTickMs),
      _flushNow,
    );
  }

  Future<void> _flushNow() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    if (_sending) {
      // 上一拍还没发完（网络慢）：不丢增量，排下一拍继续
      if (_pendDx != 0 ||
          _pendDy != 0 ||
          _pendScrollX != 0 ||
          _pendScrollY != 0 ||
          _pendFrameCommands.isNotEmpty) {
        _ensureSendTimer();
      }
      return;
    }
    final session = widget.session;
    if (session == null) {
      _resetPending();
      return;
    }
    final hasPending =
        _pendDx != 0 ||
        _pendDy != 0 ||
        _pendScrollX != 0 ||
        _pendScrollY != 0 ||
        _pendFrameCommands.isNotEmpty;
    if (!hasPending) return;
    if (!widget.connected) {
      _resetPending();
      _notifyOfflineThrottled();
      return;
    }

    _sending = true;
    try {
      // 出站顺序：先移动后点击（先到位后点击）——管道 FIFO 保证 PC 执行序。
      final ix = _pendDx.truncate();
      final iy = _pendDy.truncate();
      _pendDx -= ix;
      _pendDy -= iy;
      if (ix != 0 || iy != 0) {
        await session.syncMouse({'a': 'move', 'dx': ix, 'dy': iy});
      }
      final sx = _pendScrollX;
      final sy = _pendScrollY;
      _pendScrollX = 0;
      _pendScrollY = 0;
      if (sx != 0 || sy != 0) {
        await session.syncMouse({'a': 'scroll', 'dx': sx, 'dy': sy});
      }
      final frames = List.of(_pendFrameCommands);
      _pendFrameCommands.clear();
      for (final f in frames) {
        await session.syncMouse(f);
      }
    } catch (_) {
      // 发送异常（socket 半死）：增量丢弃不重试——移动下一帧自愈，
      // 点击重发有误触风险（宁少勿多）。RtSession 自会走重连梯。
      _resetPending();
    } finally {
      _sending = false;
    }
  }

  void _resetPending() {
    _pendDx = 0;
    _pendDy = 0;
    _pendScrollX = 0;
    _pendScrollY = 0;
    _pendFrameCommands.clear();
  }

  void _notifyOfflineThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastOfflineNotifyAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastOfflineNotifyAt = now;
    widget.onNotify('未连接电脑，触摸板不可用');
  }

  // ================= 提示层 =================

  void _flashAction(String label) {
    if (!mounted) return; // dispose 兜底路径（cancelAll 补 release）会走到这
    _actionTimer?.cancel();
    setState(() => _actionLabel = label);
    _actionTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _actionLabel = null);
    });
  }

  void _flashScroll() {
    if (!mounted) return;
    // 滚轮是连续动作：700ms 内只闪一次，避免 chip 抖频
    final now = DateTime.now();
    if (now.difference(_lastScrollFlashAt) <
        const Duration(milliseconds: 700)) {
      return;
    }
    _lastScrollFlashAt = now;
    _flashAction('滚轮');
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        children: [
          // 手势面本体：极淡的中心标记给「不用看」时的一点方位感
          if (widget.showCenterMark)
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    Icons.mouse_outlined,
                    size: 30,
                    color: c.textMuted.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          if (_showHint)
            Center(
              child: IgnorePointer(child: _GestureLegend(cs: cs)),
            ),
          // 底部动作提示 chip
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _actionLabel != null ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _actionLabel ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 触摸板灵敏度 sheet（触摸板页 / 横屏手柄页共用）。
Future<void> showRtSensitivitySheet(
  BuildContext context, {
  required double value,
  required ValueChanged<double> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      return StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '触摸板灵敏度',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '指针速度倍率（触摸板自己的加速度曲线，不受电脑设置影响）',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                Slider(
                  value: value,
                  min: kRtPadSensitivityMin,
                  max: kRtPadSensitivityMax,
                  divisions: 21,
                  label: value.toStringAsFixed(1),
                  onChanged: (v) {
                    setSheet(() => value = v);
                    onChanged(v);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// 手势图例（首次进入显示，首次触摸即隐藏）。
class _GestureLegend extends StatelessWidget {
  const _GestureLegend({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 26, color: cs.primary),
          const SizedBox(height: 10),
          Text(
            '触摸板已就绪',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          // Wrap：竖屏一行排不下时自动折行，横屏一行排开
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: const [
              _LegendChip('单指 移动'),
              _LegendChip('轻点 左键'),
              _LegendChip('双指 滚动'),
              _LegendChip('双指点 右键'),
              _LegendChip('长按拖 拖拽'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 触摸板页的圆形小按钮（退出 / 灵敏度 / 编辑等浮层动作）。共用。
class RtPadChipButton extends StatelessWidget {
  const RtPadChipButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
