// lib/lab/demos/remotetype/rt_touchpad_view.dart
//
// 触摸板页 UI：全屏手势面 + 极简浮层（退出 / 灵敏度 / 连接点 + 动作提示）。
// 为「躺床上不用看」设计：一切反馈以触感优先（HapticFeedback），视觉提示
// 只做辅助——手势判定全在 rt_touchpad_engine（纯逻辑），本文件只做搬运：
//   Listener 指针事件 → engine.down/move/up/cancel
//   engine 回调 → 合批（kRtPadSendTickMs）→ session.syncMouse / syncHotkey
//
// 横屏：全出血布局无方向假设，配合页面层 LineOrientation.enableAll 生效。
// 断连不拦手势：本地照常判定，仅在发送处静默丢弃并低频提示（回连自愈）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/context/colors.dart';
import 'rt_constants.dart';
import 'rt_session.dart';
import 'rt_touchpad_engine.dart';

class RtTouchpadView extends StatefulWidget {
  const RtTouchpadView({
    super.key,
    required this.session,
    required this.connected,
    required this.sensitivity,
    required this.onSensitivityChanged,
    required this.onExit,
    required this.onNotify,
  });

  /// 活会话（页面层保证仅在已连接状态下进入本页；重连期间可能短暂为
  /// 旧会话——syncMouse 对死 socket 返回 false，安全）。
  final RtSession? session;
  final bool connected;
  final double sensitivity;
  final ValueChanged<double> onSensitivityChanged;
  final VoidCallback onExit;
  final void Function(String message) onNotify;

  @override
  State<RtTouchpadView> createState() => _RtTouchpadViewState();
}

class _RtTouchpadViewState extends State<RtTouchpadView>
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
  bool _showHint = true;
  String? _actionLabel;
  Timer? _actionTimer;
  DateTime _lastOfflineNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScrollFlashAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(covariant RtTouchpadView oldWidget) {
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
    _engine.down(e.pointer, e.localPosition.dx, e.localPosition.dy,
        e.timeStamp.inMilliseconds);
  }

  void _onPointerMove(PointerMoveEvent e) {
    _engine.move(e.pointer, e.localPosition.dx, e.localPosition.dy,
        e.timeStamp.inMilliseconds);
  }

  void _onPointerUp(PointerUpEvent e) {
    _engine.up(e.pointer, e.localPosition.dx, e.localPosition.dy,
        e.timeStamp.inMilliseconds);
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
    final hasPending = _pendDx != 0 ||
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
    if (now.difference(_lastScrollFlashAt) < const Duration(milliseconds: 700)) {
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
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Stack(
          children: [
            // 手势面本体：极淡的中心标记给「不用看」时的一点方位感
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
                child: IgnorePointer(
                  child: _GestureLegend(cs: cs),
                ),
              ),
            // 顶部浮层：左连接点 · 右灵敏度/退出
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    _ConnDot(connected: widget.connected, cs: cs),
                    const Spacer(),
                    _PadChipButton(
                      icon: Icons.tune,
                      tooltip: '触摸板灵敏度',
                      onTap: () => _openSensitivitySheet(context),
                    ),
                    const SizedBox(width: 8),
                    _PadChipButton(
                      icon: Icons.keyboard,
                      tooltip: '返回打字',
                      onTap: widget.onExit,
                    ),
                  ],
                ),
              ),
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
      ),
    );
  }

  Future<void> _openSensitivitySheet(BuildContext context) async {
    var value = widget.sensitivity;
    await showModalBottomSheet<void>(
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
                    style: Theme.of(sheetCtx).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '指针速度倍率（触摸板自己的加速度曲线，不受电脑设置影响）',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    value: value,
                    min: kRtPadSensitivityMin,
                    max: kRtPadSensitivityMax,
                    divisions: 21,
                    label: value.toStringAsFixed(1),
                    onChanged: (v) {
                      setSheet(() => value = v);
                      widget.onSensitivityChanged(v);
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

/// 连接状态点（不用看也要能瞥一眼）。
class _ConnDot extends StatelessWidget {
  const _ConnDot({required this.connected, required this.cs});

  final bool connected;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected
                  ? const Color(0xFF34A853)
                  : cs.error.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? '已连接' : '未连接',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 触摸板页的圆形小按钮（退出 / 灵敏度）。
class _PadChipButton extends StatelessWidget {
  const _PadChipButton({
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
