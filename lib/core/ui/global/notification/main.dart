// 全局顶部通知 —— 毛玻璃胶囊（v2 重设计，取代 v1 边框主义）。
//
// 设计要点（胶囊玻璃主义，原型见 temp/toast-redesign.html）：
//   · 从屏幕顶部弹簧滑入，rootOverlay 挂载 → 高于所有 route / dialog / sheet
//   · 无描边：毛玻璃材质（BackdropFilter blur 24 + saturate 1.7）+ 半透明染色底，
//     语义色只落在图标上 —— 通知读作系统层浮层，而不是页面里的一块内容
//   · 胶囊形体：内容自适应宽度（≤ 屏宽 - 32，v1 的 520 全宽卡片废止）；
//     r=24 一个值同时兜住单行全圆 / 多行大圆角
//   · 语义色固定（警告黄 / 成功绿 / 失败红 / 信息蓝），不随主题染色 ——
//     通知是系统级信号，固定色才能跨 7 套主题保持辨识度（同 v1 策略）；
//     明暗两套玻璃底按 Theme.brightness 自动切换。
//   · 触屏肌肉记忆：点按提前关闭 · 按住暂停倒计时 · 上滑甩除；
//     新通知到来立即顶替旧通知（同一时刻至多一条）
//   · 可选动作位：action + onAction，点击动作先收通知再回调（如「撤销」）
//
// 用法：
//   AppNotification.show(context, '已切换到茶禅主题',
//       type: AppNotificationType.success);
//   AppNotification.show(context, '连接断开', type: AppNotificationType.error);
//   AppNotification.show(context, 'Banner 已移除',
//       type: AppNotificationType.success, action: '撤销', onAction: onUndo);

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 通知语义类型 —— 决定图标颜色
enum AppNotificationType { success, warning, error, info }

/// 全局顶部通知入口（静态门面，内部持有当前 OverlayEntry）
class AppNotification {
  AppNotification._();

  /// 当前展示中的 entry（同一时刻至多一条，新通知顶替旧通知）
  static OverlayEntry? _entry;

  /// 弹出顶部通知。
  ///
  /// [type] 语义类型（默认 info）；[duration] 停留时长，到时自动滑出；
  /// [action] 可选动作文字（如「撤销」），点击后先收通知再回调 [onAction]。
  static void show(
    BuildContext context,
    String message, {
    AppNotificationType type = AppNotificationType.info,
    Duration duration = const Duration(milliseconds: 2600),
    String? action,
    VoidCallback? onAction,
  }) {
    // rootOverlay：通知要盖住 push 出去的页面和 dialog，不能落在当前 route 的
    // 局部 Overlay 里。
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      debugPrint('[AppNotification] no overlay available, drop: $message');
      return;
    }

    // 旧通知（含正在退场动画中的）立即移除，给新通知让位。
    // remove() 会卸载旧胶囊 → 动画 ticker 被取消 → 旧胶囊的退场完成回调
    // （TickerFuture 被 cancel 后永不完成）不会触发，不会误删新通知。
    _removeNow();

    // entry 引用直接闭包进胶囊：退场动画播完后由胶囊自己 remove 自己，
    // 与静态 _entry 指针解耦（静态指针只服务"新顶替旧"这条路径）。
    // late final 先声明再赋值 —— Dart 禁止在自身初始化器里引用局部变量。
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NotificationCard(
        message: message,
        type: type,
        duration: duration,
        action: action,
        onAction: onAction,
        onDismissed: () {
          // 身份守卫：本条若已被 _removeNow() 顶替，迟到的回调（reverse 收尾 /
          // fling Timer 晚一帧触发）不得清掉新通知的 _entry、不得二次 remove
          if (!identical(_entry, entry)) return;
          _entry = null;
          entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// 立即移除当前通知（不等退场动画）
  static void _removeNow() {
    _entry?.remove();
    _entry = null;
  }
}

/// 单条通知胶囊：滑入 → 停留 → 滑出，全程自管理。
///
/// 动效与手势对应原型的落地参数表：
/// 进场 420ms easeOutBack（下移归位 + scale .96 + fade）、退场 230ms easeIn、
/// 停留 2600ms、按住暂停倒计时、上滑甩除、点按关闭。
class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
    this.action,
    this.onAction,
  });

  final String message;
  final AppNotificationType type;
  final Duration duration;
  final String? action;
  final VoidCallback? onAction;

  /// 通知彻底离场后回调（清 AppNotification._entry 引用）
  final VoidCallback onDismissed;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  Timer? _timer;
  bool _dismissed = false;

  // 按住暂停倒计时：deadline - now 即剩余时长
  DateTime _deadline = DateTime.now();
  Duration _remain = Duration.zero;
  bool _holding = false;

  // 上滑甩除：跟手位移（松手后经 TweenAnimationBuilder 回弹 / 甩出）
  double _dragRaw = 0;
  double _dragTarget = 0;
  bool _dragging = false;
  Timer? _flingTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 230),
    );
    // easeOutBack 起手带回弹，比纯 easeOut 更有"弹出来打招呼"的质感
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(curve);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(curve);
    _controller.forward();
    _armTimer(widget.duration);
  }

  // ---- 倒计时（支持按住暂停）----

  void _armTimer(Duration d) {
    _timer?.cancel();
    _remain = d;
    _deadline = DateTime.now().add(d);
    _timer = Timer(d, _dismiss);
  }

  void _pauseTimer() {
    final t = _timer;
    if (t == null) return;
    t.cancel();
    _timer = null;
    _remain = _deadline.difference(DateTime.now());
  }

  void _resumeTimer() {
    if (_timer != null || _dismissed) return;
    // 剩余太短就给个保底时长，避免松手瞬间就消失
    _armTimer(
      _remain < const Duration(milliseconds: 600)
          ? const Duration(milliseconds: 600)
          : _remain,
    );
  }

  // ---- 关闭路径 ----

  /// 点按提前关闭 / 到时自动关闭：播退场动画后再摘 entry
  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _timer?.cancel();
    _controller.reverse().then((_) => widget.onDismissed());
  }

  /// 上滑甩除：不走退场动画，跟手飞出后直接摘 entry
  void _flingAway() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _timer?.cancel();
    setState(() => _dragTarget = -260);
    _flingTimer = Timer(const Duration(milliseconds: 240), widget.onDismissed);
  }

  void _onActionTap() {
    final cb = widget.onAction;
    _dismiss();
    cb?.call();
  }

  // ---- 手势 ----

  /// 任意按下即暂停倒计时（按住看清楚），松开恢复
  void _press(bool down) {
    if (_dismissed || !mounted) return;
    setState(() => _holding = down);
    if (down) {
      _pauseTimer();
    } else {
      _resumeTimer();
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_dismissed) return;
    setState(() {
      _dragging = true;
      _dragRaw = 0;
      _dragTarget = 0;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dismissed || !_dragging) return;
    // 只向上跟手；向下不跟随，防误触
    _dragRaw += details.delta.dy;
    setState(() {
      _dragTarget = math.max(-140.0, math.min(0.0, _dragRaw * 0.75));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dismissed || !_dragging) return;
    _dragging = false;
    final vy = details.velocity.pixelsPerSecond.dy;
    if (_dragTarget < -42 || vy < -550) {
      _flingAway();
    } else {
      // 回弹归位；倒计时由 pointerup 的 _press(false) 恢复
      setState(() => _dragTarget = 0);
    }
  }

  /// 竞技场被系统手势夺走（如 Android 顶部边缘返回）时回弹归位，
  /// 否则 _dragging 卡在 true、胶囊僵在半拖位移
  void _onPanCancel() {
    if (_dismissed || !_dragging) return;
    setState(() {
      _dragging = false;
      _dragTarget = 0;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = _NotificationStyle.of(widget.type, dark: dark);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          // 状态栏下方再留 12px 呼吸
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.topCenter,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                child: FadeTransition(
                  opacity: _fade,
                  child: ConstrainedBox(
                    // 内容自适应宽度，至多吃满屏宽 - 32
                    constraints: BoxConstraints(
                      maxWidth: math.max(
                        0,
                        MediaQuery.of(context).size.width - 32,
                      ),
                    ),
                    child: Listener(
                      // Listener 在 GestureDetector 外层：按下即暂停，
                      // 不与 tap / pan 的手势竞技场裁决冲突
                      onPointerDown: (_) => _press(true),
                      onPointerUp: (_) => _press(false),
                      onPointerCancel: (_) => _press(false),
                      child: GestureDetector(
                        onTap: _dismiss,
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        onPanCancel: _onPanCancel,
                        child: TweenAnimationBuilder<double>(
                          // 拖拽层：跟手时 duration 0 逐帧贴手指；
                          // 松手后同一 tween 播回弹（→0）或甩出（→-260）。
                          // 毛玻璃 blur σ 随位移衰减（见 _buildCapsule）
                          tween: Tween<double>(end: _dragTarget),
                          duration: _dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) {
                            return Opacity(
                              opacity: math.max(
                                0.0,
                                math.min(1.0, 1 + v / 260.0),
                              ),
                              child: Transform.translate(
                                offset: Offset(0, v),
                                child: _buildCapsule(style, v),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapsule(_NotificationStyle style, double dragV) {
    // r=24：单行高约 40 → 视觉上全圆胶囊；多行自动退为大圆角
    final radius = BorderRadius.circular(24);
    // blur σ 随上滑位移衰减：BackdropFilter 不吃祖先 Opacity，
    // 不同步衰减会在半透明时留下一块全强度的"模糊鬼影"
    final sigma = math.max(0.0, 24.0 * (1 + dragV / 260.0));
    return Container(
      // 阴影画在裁剪外层，避免被 ClipRRect 裁掉
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: _holding ? style.shadowHold : style.shadow,
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // 毛玻璃：blur 24 + 饱和 1.7（ColorFilter 即 ImageFilter，可直接组合）
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            inner: ColorFilter.saturation(1.7),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: radius,
              border: Border.all(color: style.edge, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, color: style.iconColor, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.message,
                    // 通知是状态条不是日志，4 行封顶 + 省略号收住极端长文本
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: style.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
                if (widget.action != null) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _onActionTap,
                    child: Text(
                      widget.action!,
                      style: TextStyle(
                        color: style.iconColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃配色：底 / 文字 / 发丝边 / 阴影按明暗两套固定；图标色按语义固定。
///
/// 主题豁免（逐项）：success/warning/error/info 四语义 × 明/暗两套固定
/// iconColor —— 通知浮层跨主题保持同一视觉语言（玻璃底 + 语义色仅上图标），
/// 不走 scheme 派生。语义 hex 沿用 v1，跨主题辨识度策略不变。
class _NotificationStyle {
  const _NotificationStyle({
    required this.background,
    required this.foreground,
    required this.edge,
    required this.shadow,
    required this.shadowHold,
    required this.iconColor,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final Color edge;
  final Color shadow;
  final Color shadowHold;
  final Color iconColor;
  final IconData icon;

  static _NotificationStyle of(AppNotificationType type, {required bool dark}) {
    // 玻璃底与文字：暗 rgba(23,23,28,.68) / 亮 rgba(250,250,252,.80)
    final background = dark ? const Color(0xAD17171C) : const Color(0xCCFAFAFC);
    final foreground = dark ? const Color(0xFFF3F4F6) : const Color(0xFF17181C);
    // 发丝内缘：暗 9% 白 / 亮 7% 黑 —— 玻璃边缘的物理暗示，不是描边
    final edge = dark ? const Color(0x17FFFFFF) : const Color(0x12141419);
    final shadow = dark ? const Color(0x73000000) : const Color(0x290F141E);
    final shadowHold = dark ? const Color(0x99000000) : const Color(0x3D0F141E);

    return switch (type) {
      AppNotificationType.success => _NotificationStyle(
        background: background,
        foreground: foreground,
        edge: edge,
        shadow: shadow,
        shadowHold: shadowHold,
        iconColor: dark ? const Color(0xFF4ADE80) : const Color(0xFF1E8E4E),
        icon: Icons.check_circle_outline,
      ),
      AppNotificationType.warning => _NotificationStyle(
        background: background,
        foreground: foreground,
        edge: edge,
        shadow: shadow,
        shadowHold: shadowHold,
        iconColor: dark ? const Color(0xFFFBBF24) : const Color(0xFFA97B00),
        icon: Icons.warning_amber_rounded,
      ),
      AppNotificationType.error => _NotificationStyle(
        background: background,
        foreground: foreground,
        edge: edge,
        shadow: shadow,
        shadowHold: shadowHold,
        iconColor: dark ? const Color(0xFFF87171) : const Color(0xFFD93036),
        icon: Icons.error_outline,
      ),
      AppNotificationType.info => _NotificationStyle(
        background: background,
        foreground: foreground,
        edge: edge,
        shadow: shadow,
        shadowHold: shadowHold,
        iconColor: dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
        icon: Icons.info_outline,
      ),
    };
  }
}
