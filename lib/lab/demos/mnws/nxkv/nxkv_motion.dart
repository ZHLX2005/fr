/// nx-kv 界面的**动效与质感原语**。
///
/// 第 2 轮验收反馈：「优化一下 uiux，从视觉和 icon 标识上优化，用一些更加圆滑的
/// icon 提升质感，同时希望动效足够 ios，足够 q 弹，比如使用贝塞尔曲线之类的方式」。
///
/// 于是这里收四件东西：
///
///   1. **曲线与时长**（[NxKvMotion]）—— iOS 的「起步猛、收尾软」用 ease-out-quint
///      近似（[NxKvMotion.glide]）；「q 弹」= 控制点越过 1 的 easeOutBack
///      （[NxKvMotion.snap]），它会在终点前**过冲**再回位 —— 过冲就是「弹」的
///      数学定义，不是感觉；
///   2. **按压回弹**（[NxKvPress]）—— 按下缩到 0.97、抬起用 [NxKvMotion.snap]
///      弹回原大；
///   3. **胶囊徽标**（[NxKvBadge]）—— 数字变化时缩放切换（q 弹），圆角给满；
///   4. **旋转箭头**（[NxKvChevron]）—— 展开态 90°，用 [NxKvMotion.snap] 转过去。
///
/// ## 为什么不用 `Curves.elasticOut`
///
/// 它过冲 10% 以上、还要来回抖两下，在 44dp 的行上像抽筋。easeOutBack 是
/// 「弹一下就停」，这才是 iOS 的手感；真需要抖的地方（几乎没有）再单独加。
///
/// ## 为什么曲线写死成 `Cubic` 而不是 `Curves.easeOutBack`
///
/// 反馈点名「贝塞尔曲线」，`Curves.easeOutBack` 内部其实也是三次贝塞尔，但它
/// 不让我们读控制点、也就没法在测试里钉住「它确实过冲」。写死成常量后
/// `nxkv_motion_test.dart` 能直接采样 `transform(t)`，把这条手感变成断言。
library;

import 'package:flutter/material.dart';

/// nx-kv 的动效常量（曲线 + 时长）。
class NxKvMotion {
  NxKvMotion._();

  /// iOS 式「先快后慢」：起步一下子就出去，收尾软软地停住。
  ///
  /// 对应 ease-out-quint（CSS `cubic-bezier(0.22, 1, 0.36, 1)`）—— Apple 自己
  /// 那套 `easeOut` 的手写近似，用在**位移 / 展开 / 淡入**这类「到位」动作上。
  static const Curve glide = Cubic(0.22, 1.00, 0.36, 1.00);

  /// q 弹：第二控制点 1.56 → 曲线越过 1 再回位（easeOutBack）。
  ///
  /// 只给**小尺寸**的东西用（按压回弹 / 徽标 / 箭头 / 展开后的子项），
  /// 大面积元素过冲会晕。
  static const Curve snap = Cubic(0.34, 1.56, 0.64, 1.00);

  /// 标准缓入缓出（Material 的 standard，用在颜色 / 描边这类不该抢戏的变化上）。
  static const Curve soft = Cubic(0.40, 0.00, 0.20, 1.00);

  /// 按下（快，别让人等）。
  static const Duration fast = Duration(milliseconds: 140);

  /// 常规（展开 / 切换 / 淡入）。
  static const Duration base = Duration(milliseconds: 240);

  /// 回弹（抬起 / 数字切换），比 [base] 长一点，弹的动作需要时间被看见。
  static const Duration slow = Duration(milliseconds: 380);
}

/// 按压回弹：按下缩一点，抬起弹回来。
///
/// 为什么不用 `InkWell`：Material 的水波纹是「圆形扩散 + 变暗」，跟 iOS 的
/// 「整块轻轻缩一下」是两套语言；而且水波纹会把圆角矩形的形状糊掉。这里用
/// 缩放 + 容器自身的背景色过渡，行是什么形状，按下去还是什么形状。
///
/// 无障碍：读屏需要标签时给 [semanticLabel]；纯装饰的行内容不要给。
class NxKvPress extends StatefulWidget {
  const NxKvPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.semanticLabel,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下时的缩放比例（0.94~0.98 之间最像 iOS；太小像抖动）。
  final double scale;

  final String? semanticLabel;
  final HitTestBehavior behavior;

  @override
  State<NxKvPress> createState() => _NxKvPressState();
}

class _NxKvPressState extends State<NxKvPress> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (!_enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          // 按下要跟手（快），抬起要弹（慢 + 过冲）
          duration: _down ? NxKvMotion.fast : NxKvMotion.slow,
          curve: _down ? NxKvMotion.glide : NxKvMotion.snap,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 胶囊徽标：数字变了就缩放切换。
///
/// 三档语气（与 nx-kv 面板 `.cnt` 同取舍）：
///   - [emphasize]：有待领 —— 主色底 + 主色字，是这一行唯一该被看见的数字；
///   - 默认：中性底色 + 次级字（成员数 / 总数这类「背景信息」）；
///   - `text` 传 `—`：数拿不到。空字符串 / null 不画。
class NxKvBadge extends StatelessWidget {
  const NxKvBadge(
    this.text, {
    super.key,
    this.emphasize = false,
    this.tooltip,
    this.fontSize = 10,
  });

  final String? text;
  final bool emphasize;
  final String? tooltip;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = text;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final fg = emphasize ? cs.primary : cs.onSurfaceVariant;
    final bg = emphasize
        ? cs.primary.withValues(alpha: 0.12)
        : cs.onSurfaceVariant.withValues(alpha: 0.08);

    final pill = AnimatedContainer(
      duration: NxKvMotion.base,
      curve: NxKvMotion.soft,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedSwitcher(
        duration: NxKvMotion.slow,
        switchInCurve: NxKvMotion.snap,
        switchOutCurve: NxKvMotion.soft,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        // key 带文字：换数字才会触发切换动画（同一个数字重绘不该弹一下）
        child: Text(
          t,
          key: ValueKey<String>(t),
          style: TextStyle(
            fontSize: fontSize,
            height: 1.25,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            color: fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return pill;
    return Tooltip(message: tooltip!, waitDuration: const Duration(milliseconds: 450), child: pill);
  }
}

/// 圆润的展开箭头：展开时转 90°，用 q 弹曲线。
///
/// 面板 `.trow.open .tw { transform: rotate(90deg) }` 是同一件事，这里补上曲线
/// —— 硬切会让人觉得「卡了一下」。
class NxKvChevron extends StatelessWidget {
  const NxKvChevron({
    super.key,
    required this.open,
    this.size = 16,
    this.color,
  });

  final bool open;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0.25 : 0,
      duration: NxKvMotion.base,
      curve: NxKvMotion.snap,
      child: Icon(Icons.chevron_right_rounded, size: size, color: color ?? Theme.of(context).colorScheme.outline),
    );
  }
}

/// 入场：淡入 + 轻微右移（抽屉拉开时内容不该「啪」一下全在）。
class NxKvEnter extends StatelessWidget {
  const NxKvEnter({super.key, required this.child, this.dx = -12, this.duration = NxKvMotion.slow});

  final Widget child;
  final double dx;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: NxKvMotion.glide,
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(dx * (1 - t), 0), child: child),
      ),
    );
  }
}

/// 图标底座：把图标放进一个小圆角方块里。
///
/// 「质感」在本轮反馈里是关键词。裸图标在 44dp 的行里显得飘，给一层
/// 8% 透明的同色底 + 圆角，眼睛会把它读成一个**物件**而不是一个符号 ——
/// 这也是 iOS 分组列表的常见做法。
class NxKvIconTile extends StatelessWidget {
  const NxKvIconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 24,
    this.iconSize = 15,
    this.radius = 8,
    this.filled = true,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final double radius;

  /// false = 不铺底色（只留图标本身，用于行尾那种「辅助」图标）。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return AnimatedContainer(
      duration: NxKvMotion.base,
      curve: NxKvMotion.soft,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: c),
    );
  }
}
