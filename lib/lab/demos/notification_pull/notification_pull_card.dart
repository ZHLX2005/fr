import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'const_notification_pull.dart';

/// 网易云音乐通知卡：折叠三行 → 下拉对齐头部 → 行距拉开（第三条贴底）
/// → 达到阈值后三条同时展开正文、小摘要褪去 → 继续下拉露出第四/五条。
///
/// 几何/进度与 docs/prototypes/notification-pull-expand.html 一一对应，
/// 卡片高度由通知数据的行数公式算出，保证内容底边始终等于卡片底边。

/// 通知卡。 [initialStage] 用于调试/截图直达某个展开档位。
class NotificationPullCard extends StatefulWidget {
  const NotificationPullCard({super.key, this.initialStage});

  /// 调试/截图用：'three' / 'four' / 'five' 或 'h180' 直达某个高度，
  /// 与 HTML 原型的 location.hash 行为一致。
  final String? initialStage;

  @override
  State<NotificationPullCard> createState() => _NotificationPullCardState();
}

class _NotificationPullCardState extends State<NotificationPullCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;

  double _h = 0;
  double _hAtDown = 0;
  double _h0 = 0, _h1 = 0, _hb = 0, _h2 = 0, _h3 = 0, _h4 = 0;
  double _ift = 27;
  List<double> _fh = const <double>[];

  int? _activePointer;
  double _startY = 0;
  bool _moved = false;
  final List<_Sample> _samples = <_Sample>[];
  double _wheelLock = 0;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() => _h = _spring.value);
      });
    _measure();
    _h = _stageHeight(widget.initialStage);
  }

  double _stageHeight(String? stage) {
    switch (stage) {
      case 'three':
        return _h2;
      case 'four':
        return _h3;
      case 'five':
        return _h4;
    }
    final RegExpMatch? m = RegExp(r'^h(\d+)$').firstMatch(stage ?? '');
    if (m != null) {
      return double.parse(m.group(1)!);
    }
    return _h0;
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  // ── 高度实测 ──
  //
  // ⚠️ 时间列宽不能用「首帧实测宽度」定死：
  // CJK 字体是异步加载的，initState 时 `TextPainter` 量到的「昨天」只有
  // 10.2px（回退字体的窄字形），字体到位后真实宽度是 23px。
  // 拿 10.2px 当列宽 → 23px 的文字被 maxLines:1 裁成「昨」。
  //
  // 所以这里不缓存实测宽度，改成由渲染端自适应：
  // 时间列用 FittedBox 之外的自适应宽度（见 _NoticeRowWidget 的时间槽）。
  void _measure() {
    _fh = List<double>.generate(kNotices.length, (int i) {
      final NotificationNotice n = kNotices[i];
      return kTitleLine + 3 + 19.0 * n.bodyLines;
    });

    final double compact3 = kCompactRow * 3 + kGap0 * 2;
    _h0 = kPadT + compact3 + kPadB;
    _h1 = kPadT + 22 + 13 + compact3 + kPadB;
    _hb = _h1 + (kGap - kGap0) * 2;
    _h2 = kPadT +
        22 +
        13 +
        _fh[0] +
        kGap +
        _fh[1] +
        kGap +
        _fh[2] +
        kPadB;
    _h3 = _h2 + kGap + _fh[3];
    _h4 = _h3 + kGap + _fh[4];
    _ift = kPadT + compact3 / 2 - 20;
  }


  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
  static double _smoothstep(double t) {
    final double x = _clamp01(t);
    return x * x * (3 - 2 * x);
  }

  static double _rubber(double x) => 62 * (1 - math.exp(-x / 130));

  // ── 指针手势（1:1 跟手 + 4px 死区 + 动量投射 + 弹簧吸附）──
  void _onPointerDown(PointerDownEvent e) {
    if (_activePointer != null) return;
    _activePointer = e.pointer;
    _spring.stop();
    _hAtDown = _h;
    _startY = e.localPosition.dy;
    _moved = false;
    _samples
      ..clear()
      ..add(_Sample(e.timeStamp.inMicroseconds / 1000.0, _startY));
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_activePointer != e.pointer) return;
    final double y = e.localPosition.dy;
    _samples.add(_Sample(e.timeStamp.inMicroseconds / 1000.0, y));
    while (_samples.length > 8) {
      _samples.removeAt(0);
    }

    final double dy = y - _startY;
    if (dy.abs() <= kDead) return;
    _moved = true;
    final double drive = dy > 0 ? dy - kDead : dy + kDead;
    double target = _hAtDown + drive;
    if (target < _h0) target = _h0 - _rubber(_h0 - target);
    if (target > _h4) target = _h4 + _rubber(target - _h4);
    setState(() => _h = target);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_activePointer != e.pointer) return;
    _activePointer = null;
    _endDrag(allowTap: true);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_activePointer != e.pointer) return;
    _activePointer = null;
    _endDrag(allowTap: false);
  }

  void _endDrag({required bool allowTap}) {
    if (!_moved) {
      if (allowTap) _toggle();
      return;
    }
    // 动量投射：按松手前的平均速度往前看 130ms，再吸附最近档
    final double vel = _dragVelocity(); // px/ms
    final double proj = _h + vel * 130;
    final List<double> stops = <double>[_h0, _h2, _h3, _h4];
    double best = stops.first;
    double bd = double.infinity;
    for (final double s in stops) {
      final double d = (proj - s).abs();
      if (d < bd) {
        bd = d;
        best = s;
      }
    }
    _springTo(best, vel * 1000);
  }

  double _dragVelocity() {
    if (_samples.length < 2) return 0;
    final _Sample a = _samples.first;
    final _Sample b = _samples.last;
    final double dt = b.tMs - a.tMs;
    if (dt < 10) return 0;
    return (b.y - a.y) / dt;
  }

  void _toggle() {
    if (_h < _h1 - 4) {
      _springTo(_h2, 0);
    } else if (_h > _h2 + 8) {
      _springTo(_h2, 0);
    } else {
      _springTo(_h0, 0);
    }
  }

  void _springTo(double target, double velocity) {
    _spring.value = _h;
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 205, damping: 29),
        _h,
        target,
        velocity,
      ),
    );
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final double now = DateTime.now().millisecondsSinceEpoch.toDouble();
    if (now - _wheelLock < 220) return;
    final List<double> stops = <double>[_h0, _h2, _h3, _h4];
    int idx = 0;
    double bd = double.infinity;
    for (int i = 0; i < stops.length; i++) {
      final double d = (_h - stops[i]).abs();
      if (d < bd) {
        bd = d;
        idx = i;
      }
    }
    final int next =
        (idx + (e.scrollDelta.dy > 0 ? 1 : -1)).clamp(0, stops.length - 1);
    if (next != idx) {
      _wheelLock = now;
      _springTo(stops[next], 0);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bool down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final bool up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;
    final List<double> stops = <double>[_h0, _h2, _h3, _h4];
    int idx = 0;
    double bd = double.infinity;
    for (int i = 0; i < stops.length; i++) {
      final double d = (_h - stops[i]).abs();
      if (d < bd) {
        bd = d;
        idx = i;
      }
    }
    final int next = (idx + (down ? 1 : -1)).clamp(0, stops.length - 1);
    _springTo(stops[next], 0);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final double ah = _clamp01((_h - _h0) / math.max(1, _h1 - _h0));
    final double ai = _smoothstep(ah / 0.45);
    final double sp = _clamp01((_h - _h1) / math.max(1, _hb - _h1));
    final double s = _smoothstep(sp);
    final double ex = _clamp01((_h - _hb) / math.max(1, _h2 - _hb));
    final double o1 = 1 - _smoothstep((ex - 0.12) / 0.50);
    final double o2 = _smoothstep(ex / 0.70);
    final double r4 = _clamp01((_h - _h2) / math.max(1, _h3 - _h2));
    final double r5 = _clamp01((_h - _h3) / math.max(1, _h4 - _h3));
    final double ch = _clamp01((_h - _h0) / math.max(1, _h2 - _h0));

    final double headH = 22 * ah;
    final double rowsTop = kPadT + headH + 13 * ah;
    final double rowsLeft = kPadL + 52 * (1 - s);
    final double rowsW = kContentW - 52 * (1 - s);
    final double iconSize = 40 - 18 * ai;
    final double iconTop = _ift + (14 - _ift) * ai;
    final double nameOpacity = _clamp01((ah - 0.72) / 0.28);

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Container(
          width: double.infinity,
          height: _h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x57000000),
                blurRadius: 34,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: kCardGradient,
                          stops: <double>[0, .46, 1],
                        ),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0x1FFFFFFF)),
                        ),
                      ),
                    ),
                  ),
                  // 应用名行（折叠态高度 0）
                  Positioned(
                    left: kPadL + 30,
                    right: kPadR + 24,
                    top: kPadT,
                    height: headH,
                    child: ClipRect(
                      child: Opacity(
                        opacity: nameOpacity,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            kAppName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kNameStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 条目
                  Positioned(
                    left: rowsLeft,
                    top: rowsTop,
                    width: rowsW,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List<Widget>.generate(kNotices.length, (int i) {
                        final bool extra = i >= 3;
                        final double pe = i == 3 ? r4 : r5;
                        final double rowH = extra
                            ? _fh[i] * pe
                            : kCompactRow + (_fh[i] - kCompactRow) * ex;
                        final double gap = extra
                            ? kGap * pe
                            : kGap0 + (kGap - kGap0) * sp;
                        final bool isLast = i == kNotices.length - 1;
                        final double timeOpacity = kNotices[i].lazyTime
                            ? _clamp01((s - .35) / .45)
                            : 1;
                        final double plusOpacity =
                            kNotices[i].plus ? _clamp01(1 - s * 2.2) : 0;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: isLast ? 0 : gap,
                          ),
                          child: _NoticeRowWidget(
                            notice: kNotices[i],
                            width: rowsW,
                            height: rowH < 0 ? 0 : rowH,
                            summaryOpacity: extra ? 0 : o1,
                            bodyOpacity: extra ? 1 : o2,
                            timeOpacity: timeOpacity,
                            plusOpacity: plusOpacity,
                          ),
                        );
                      }),
                    ),
                  ),
                  // 图标：折叠态左侧大字牌 → 展开态头部小图标
                  Positioned(
                    left: 16,
                    top: iconTop,
                    width: iconSize,
                    height: iconSize,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12 - 5 * ai),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x47000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12 - 5 * ai),
                        child: CustomPaint(painter: _MusicIconPainter()),
                      ),
                    ),
                  ),
                  // 箭头：随下拉进度连续翻转
                  Positioned(
                    top: 15,
                    right: 14,
                    width: 18,
                    height: 18,
                    child: Transform.rotate(
                      angle: math.pi * ch,
                      child: Center(
                        child: CustomPaint(
                          size: const Size(12, 8),
                          painter: _ChevronPainter(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeRowWidget extends StatelessWidget {
  const _NoticeRowWidget({
    required this.notice,
    required this.width,
    required this.height,
    required this.summaryOpacity,
    required this.bodyOpacity,
    required this.timeOpacity,
    required this.plusOpacity,
  });

  final NotificationNotice notice;
  final double width;
  final double height;
  final double summaryOpacity;
  final double bodyOpacity;
  final double timeOpacity;
  final double plusOpacity;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: height,
        width: width,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            // 标题 + 紧凑摘要同一行：用 Row 保证 7px 间距，不依赖文字实测宽度
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(0, width - 62),
                    ),
                    child: Text(
                      notice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kTitleStyle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Opacity(
                      opacity: summaryOpacity,
                      child: Text(
                        notice.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kInlineStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  // 时间槽：宽度由文字自身决定（不预测量），
                  // 末尾 timeRight 让开右上角箭头 / +N。
                  Padding(
                    padding: EdgeInsets.only(right: notice.timeRight),
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: <Widget>[
                        Opacity(
                          opacity: timeOpacity,
                          child: Text(
                            notice.time,
                            maxLines: 1,
                            style: kTimeStyle,
                          ),
                        ),
                        if (notice.plus)
                          Opacity(
                            opacity: plusOpacity,
                            child: Text(
                              '+ 2',
                              maxLines: 1,
                              style: kPlusStyle,
                            ),
                          ),
                      ],
                    ),
                  ),                ],
              ),
            ),
            // 正文：钉在标题下方，靠行高增长被"揭出来"
            Positioned(
              left: 0,
              right: 0,
              top: 23,
              child: Opacity(
                opacity: bodyOpacity,
                child: Text(
                  notice.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kBodyStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sample {
  const _Sample(this.tMs, this.y);
  final double tMs;
  final double y;
}

class _MusicIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double k = size.width / 48;
    canvas.save();
    canvas.scale(k, k);

    final RRect bg = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 48, 48),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(48, 48),
          const <Color>[kMusicIconRed, kMusicIconRedDark],
        ),
    );

    final Paint stroke = Paint()
      ..color = const Color(0xF2FFFFFF)
      ..strokeWidth = 2.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(const Offset(24, 24), 13.4, stroke);

    final Path note = Path()
      ..moveTo(27.4, 15.6)
      ..lineTo(27.4, 27.7)
      ..arcToPoint(
        const Offset(24.7, 23.84),
        radius: const Radius.circular(4.1),
        largeArc: true,
        clockwise: true,
      );
    canvas.drawPath(note, stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = kChevronColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()
      ..moveTo(1, 1.5)
      ..lineTo(6, 6.5)
      ..lineTo(11, 1.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
