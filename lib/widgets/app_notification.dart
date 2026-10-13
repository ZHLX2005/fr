// 全局顶部通知栏 —— 替代底部黑色 SnackBar 的全局提示组件。
//
// 设计要点（边框主义）：
//   · 从屏幕顶部滑入，rootOverlay 挂载 → 高于所有 route / dialog / sheet
//   · 1.5px 语义色实线边框 + 低饱和同色系染色底，边框就是视觉主角
//   · 语义色固定（警告黄 / 成功绿 / 失败红 / 信息蓝），不随主题染色 ——
//     通知是系统级信号，固定色才能跨 7 套主题保持辨识度（zen 的 warning
//     是米色、暗黑的 success 是灰绿，直接吃 AppColorsExtension 会失真）；
//     明暗两套色值按 Theme.brightness 自动切换。
//   · 点击通知可提前关闭；新通知到来立即顶替旧通知（同一时刻至多一条）
//
// 用法：
//   AppNotification.show(context, '已切换到茶禅主题',
//       type: AppNotificationType.success);
//   AppNotification.show(context, '连接断开', type: AppNotificationType.error);

import 'dart:async';

import 'package:flutter/material.dart';

/// 通知语义类型 —— 决定边框 / 图标 / 染色底的颜色
enum AppNotificationType { success, warning, error, info }

/// 全局顶部通知栏入口（静态门面，内部持有当前 OverlayEntry）
class AppNotification {
  AppNotification._();

  /// 当前展示中的 entry（同一时刻至多一条，新通知顶替旧通知）
  static OverlayEntry? _entry;

  /// 弹出顶部通知。
  ///
  /// [type] 语义类型（默认 info）；[duration] 停留时长，到时自动滑出。
  static void show(
    BuildContext context,
    String message, {
    AppNotificationType type = AppNotificationType.info,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    // rootOverlay：通知要盖住 push 出去的页面和 dialog，不能落在当前 route 的
    // 局部 Overlay 里。
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      debugPrint('[AppNotification] no overlay available, drop: $message');
      return;
    }

    // 旧通知（含正在退场动画中的）立即移除，给新通知让位。
    // remove() 会卸载旧卡片 → 动画 ticker 被取消 → 旧卡片的退场完成回调
    // （TickerFuture 被 cancel 后永不完成）不会触发，不会误删新通知。
    _removeNow();

    // entry 引用直接闭包进卡片：退场动画播完后由卡片自己 remove 自己，
    // 与静态 _entry 指针解耦（静态指针只服务"新顶替旧"这条路径）。
    // late final 先声明再赋值 —— Dart 禁止在自身初始化器里引用局部变量。
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NotificationCard(
        message: message,
        type: type,
        duration: duration,
        onDismissed: () {
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

/// 单条通知卡片：滑入 → 停留 → 滑出，全程自管理
class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppNotificationType type;
  final Duration duration;

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
  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
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
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  /// 点按提前关闭 / 到时自动关闭：播退场动画后再摘 entry
  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _timer?.cancel();
    _controller.reverse().then((_) => widget.onDismissed());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: SafeArea(
            bottom: false,
            child: Padding(
              // 状态栏下方再留 12px 呼吸；横屏 / 宽屏时居中限宽
              padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GestureDetector(
                    onTap: _dismiss,
                    child: _buildCard(style),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(_NotificationStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.border, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.accent, size: 20),
          const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}

/// 语义配色（边框主义的核心：边框/图标 = 高饱和语义色，底 = 低饱和染色）
class _NotificationStyle {
  const _NotificationStyle({
    required this.border,
    required this.accent,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color border;
  final Color accent;
  final Color background;
  final Color foreground;
  final IconData icon;

  static _NotificationStyle of(AppNotificationType type, {required bool dark}) {
    if (dark) {
      return switch (type) {
        AppNotificationType.success => _NotificationStyle(
          border: const Color(0xFF4ADE80),
          accent: const Color(0xFF4ADE80),
          background: const Color(0xF0112A1D),
          foreground: const Color(0xFFF2F2F2),
          icon: Icons.check_circle_outline,
        ),
        AppNotificationType.warning => _NotificationStyle(
          border: const Color(0xFFFBBF24),
          accent: const Color(0xFFFBBF24),
          background: const Color(0xF02E2410),
          foreground: const Color(0xFFF2F2F2),
          icon: Icons.warning_amber_rounded,
        ),
        AppNotificationType.error => _NotificationStyle(
          border: const Color(0xFFF87171),
          accent: const Color(0xFFF87171),
          background: const Color(0xF02E1517),
          foreground: const Color(0xFFF2F2F2),
          icon: Icons.error_outline,
        ),
        AppNotificationType.info => _NotificationStyle(
          border: const Color(0xFF60A5FA),
          accent: const Color(0xFF60A5FA),
          background: const Color(0xFF14202F),
          foreground: const Color(0xFFF2F2F2),
          icon: Icons.info_outline,
        ),
      };
    }
    return switch (type) {
      AppNotificationType.success => _NotificationStyle(
        border: const Color(0xFF34A853),
        accent: const Color(0xFF1E8E4E),
        background: const Color(0xFFEBF7F0),
        foreground: const Color(0xFF1F2430),
        icon: Icons.check_circle_outline,
      ),
      AppNotificationType.warning => _NotificationStyle(
        border: const Color(0xFFE6A700),
        accent: const Color(0xFFA97B00),
        background: const Color(0xFFFDF4DC),
        foreground: const Color(0xFF1F2430),
        icon: Icons.warning_amber_rounded,
      ),
      AppNotificationType.error => _NotificationStyle(
        border: const Color(0xFFE5484D),
        accent: const Color(0xFFD93036),
        background: const Color(0xFFFCEDEB),
        foreground: const Color(0xFF1F2430),
        icon: Icons.error_outline,
      ),
      AppNotificationType.info => _NotificationStyle(
        border: const Color(0xFF3B82F6),
        accent: const Color(0xFF2563EB),
        background: const Color(0xFFEAF2FD),
        foreground: const Color(0xFF1F2430),
        icon: Icons.info_outline,
      ),
    };
  }
}
