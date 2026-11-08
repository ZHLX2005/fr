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

  /// 是否正在拖动（指针按下后越过死区）。
  ///
  /// 拖动一开始，布局就整体切到展开排布，图标透明后渐入 ——
  /// 否则会看到左边大字牌和左上角小图标的重影。
  bool _dragging = false;

  /// 是否已切换到「展开排布」。
  ///
  /// 切换是**离散**的：触发拖动的那一帧完成，不做逐像素过渡
  /// （逐帧连贯反而显得拖不动）。松手后保持切换态，直到卡片收回
  /// 折叠态才复位。
  bool _switched = false;

  /// 布局切换**那一刻**的卡片高度。
  ///
  /// 拖动的基准高度必须是它 —— 每次都拿 _h1 当基准的话，第二次拖动
  /// （卡片已经展开到 255px 时）会突然从 129 重新起算，高度暴跌一截
  /// （「从最开始开始触发」的 bug）。锚在切换瞬间的高度上，后续拖动
  /// 就是纯增量，连续拖动不会跳。
  double _switchBase = 0;

  final List<_Sample> _samples = <_Sample>[];
  double _wheelLock = 0;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _h = _spring.value;
          // 回弹到折叠态时把布局复位（否则停在「展开排布 + 折叠高度」，
          // 三条小正文放不下 —— 就是那个只剩两条的负状态）。
          if (_switched && _h <= _h0 + 0.5) {
            _switched = false;
            _h = _h0;
          }
        });
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

  /// C2 连续的平滑曲线（smootherstep）。
  ///
  /// 比 [_smoothstep] 的一阶导在两端都为 0，二阶导也连续 —— 渐入时
  /// 起手和收尾都没有「顿一下」的加速度突变，视觉上更像一次呼吸。
  static double _smootherstep(double t) {
    final double x = _clamp01(t);
    return x * x * x * (x * (x * 6 - 15) + 10);
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
    if (!_dragging) {
      // 越过死区 = 正式进入拖动：
      //   ① 布局整体切到展开排布（离散切换），图标 / 应用名此刻透明，
      //      随后随拖动渐入；
      //   ② 卡片高度**同时**跳到 H1 —— 切过去后头部占了 22+13px，
      //      三条小正文需要 66px；不一起长过去，第三条会被卡片底边裁掉
      //      （只剩两条的「负状态」）。
      _dragging = true;
      _switched = true;
      _h = math.max(_h, _h1);
      // 锚住切换瞬间的高度 —— 后续拖动都以此为基准（纯增量）。
      _switchBase = _h;
    }
    _moved = true;
    final double drive = dy > 0 ? dy - kDead : dy + kDead;
    // 高度基准：切换后用「切换瞬间的高度」继续加 —— 纯增量，连续拖动
    // 不会跳。不能用 _hAtDown + drive（会把高度拉回折叠区），也不能
    // 每次都用 _h1（第二次拖动会从 129 重新起算 → 高度暴跌）。
    final double base = _switched ? _switchBase : _hAtDown;
    double target = base + drive;
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
    // 拖动结束：图标回到「静态可见」的状态（松手后卡片已展开到位）。
    // 若最终吸附回折叠态，布局也复位到静态排布。
    setState(() {
      _dragging = false;
      if (_h <= _h0 + 1) {
        _switched = false;
        _h = _h0;
      }
    });
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
    final double sp = _clamp01((_h - _h1) / math.max(1, _hb - _h1));
    final double s = _smoothstep(sp);
    final double ex = _clamp01((_h - _hb) / math.max(1, _h2 - _hb));
    final double o1 = 1 - _smoothstep((ex - 0.12) / 0.50);
    // 正文渐入：改用 smootherstep —— 一阶导两端为 0，起手/收尾无加速度突变，
    // 比 smoothstep 多一层「渐入渐出」的呼吸感；再把整段前移，让正文更早
    // 开始变深（真机参考图实测：展开中途正文有效不透明度已到 ~0.90）。
    final double o2 = _smootherstep((ex - 0.04) / 0.62);
    final double r4 = _clamp01((_h - _h2) / math.max(1, _h3 - _h2));
    final double r5 = _clamp01((_h - _h3) / math.max(1, _h4 - _h3));
    final double ch = _clamp01((_h - _h0) / math.max(1, _h2 - _h0));

    // ── 拖动起始 = 一次「布局切换」，不是渐变 morph ──
    //
    // 触发拖动的那一帧，整个布局直接切到展开态的排布：
    //   · 图标从左侧大字牌 → 第一行左上角小图标
    //   · 应用名出现在图标右侧
    //   · 三行正文整体下移，给头部让出位置
    //
    // 这一步是**离散的**：_switched 从 false 翻到 true 的瞬间完成。
    // 逐帧连贯反而显得「拖不动」—— 要的是「一触发就换排布」。
    //
    // 切过去之后，图标 / 应用名是**透明**的（depth 从 0 起），随拖动渐入；
    // 三行条目的「小标题 → 正文」切换仍按原有的 o1/o2 走。
    final bool snapped = _switched;

    // 布局用「展开态」的几何量算（ah=1 那一组），保证拖到位的效果
    // 与「渐进拖到位」完全一致 —— 切换只是把它提前发生。
    final double layoutAh = snapped ? 1.0 : ah;

    final double headH = 22 * layoutAh;
    final double rowsTop = kPadT + headH + 13 * layoutAh;

    // 切换后额外拖过的距离 —— 图标渐入、缩进回收都以此为进度。
    final double dragPastSwitch = math.max(0, _h - _h1);

    // 文字缩进（左侧那块让位空间）：**第一帧不变**，随拖动连贯地收回。
    //
    // ⚠️ 不能用 s（= 行距阶段的进度）驱动：那一段区间只有 H1→HB = 22px，
    // 切换后拖 11px 缩进就从 52 掉到 26 —— 视觉上就是「左边消失了」。
    //
    // 这里按**切换后额外拖过的像素**推进（kIndentSpan = 60px）：
    // 切换瞬间缩进仍是 52（一动不动），之后随拖动平滑收完到 0。
    final double indent = 52.0 * (1 - _smootherstep(dragPastSwitch / kIndentSpan));
    final double rowsLeft = kPadL + indent;
    final double rowsW = kContentW - indent;

    // 图标几何：静态时是左侧 40px 大字牌；切换后是第一行左上角的小图标。
    final double iconSize = 40 - 22 * layoutAh;
    final double iconTop = _ift + (14 - _ift) * layoutAh;

    // 图标 / 应用名的「由浅变深」进度：**切换那一帧是 0（透明）**，
    // 随拖动逐渐变实。
    //
    // ⚠️ 不能用 ah 派生：切换时卡片高度已经跳到 H1（ah=1），ah 恒为 1，
    // 图标会一上来就完全显形 —— 就没有「透明后渐入」了。
    // 这里用**切换后额外拖过的距离**：切换瞬间为 0，继续往下拖才渐入。
    final double depth = _smootherstep(dragPastSwitch / kFadeInSpan);

    // 应用名：随头部浮起渐入（ah=0 时行高为 0，本来就无处可显）。
    final double nameOpacity = depth;

    // 图标可见度：静态时**完全可见**（图标就在左侧原位，是卡片的主体）。
    // 一旦开始拖动：图标已「极快」移到第一行左上角，此时先归零再渐入 ——
    // 避免大图标变身成头部小图标时出现两个图标的重影。
    final double iconAlpha = _dragging ? depth : 1.0;

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
                    // 切换到展开排布后，应用名排到图标右侧（同一行）；
                    // 静态态则在头部行内（图标还在左侧大字牌位置）。
                    left: snapped
                        ? kIconLeft + iconSize + kIconNameGap
                        : kPadL + 30,
                    right: kPadR + 24,
                    top: snapped ? iconTop - 2 : kPadT,
                    height: snapped ? 22.0 : headH,
                    child: ClipRect(
                      child: Opacity(
                        // 应用名与正文同深浅（共享 depth），
                        // 但比正文略晚显形 —— 头部先对齐，名字才浮出来。
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
                  // 图标：静态时是左侧大字牌 → 拖动时极快移到第一行左上角 → 展开态是头部小图标
                  Positioned(
                    left: kIconLeft,
                    top: iconTop,
                    width: iconSize,
                    height: iconSize,
                    child: Opacity(
                      // 触发拖动时从 0 开始渐入（静态时完全可见）。
                      opacity: iconAlpha,
                      child: Container(
                        key: const ValueKey<String>('notification-pull-icon'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12 - 5 * (snapped ? 0.62 : 0)),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x47000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12 - 5 * (snapped ? 0.62 : 0)),
                          child: CustomPaint(painter: _MusicIconPainter()),
                        ),
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
