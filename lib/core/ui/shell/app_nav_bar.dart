// 应用级页面导航（AppNavBar）—— 全应用统一的页头导航组件。
//
// 三种样式（其他特殊样式的 nav 一律收敛为这里的变体，不得再造第三套手写实现）：
//   - AppNavBar.standard : AppBar 规范样式（返回 + 左对齐标题 + actions）。
//                          规范样板 = 远程输入设置页（RtSettingsPage）。
//   - AppNavBar.floating : 全出血内容上的浮层行（SafeArea + 返回钮 + 标题插槽 + actions）。
//                          服务 rt 主页头部、line 全出血页、focus 计时头部等。
//   - AppNavBar.pill     : 浮卡胶囊条（圆角卡：返回 + 标题插槽 + trailing）。
//                          服务阅读器顶栏这类"卡片式"页头。
//
// 色源约束：standard/pill 默认走 ColorScheme；确需主题豁免（如阅读器纸质色）
// 通过显式颜色参数在调用点声明，不在组件内写死。
//
// 返回逻辑：standard 走 AppBar 自带 automaticallyImplyLeading；floating/pill
// 传 onBack 即显示返回钮，配合 `context.navCanPop`（lib/core/nav/nav_route.dart）
// 在根页自动隐藏。

import 'package:flutter/material.dart';

import '../../nav/nav_route.dart';
import '../atomic/base_icon_button.dart';

/// floating 返回钮形态。
enum NavBackStyle {
  /// 圆形描边钮（BaseIconButton.outline）——浮在浅色画布上。
  solid,

  /// 裸图标（无底色）——浮在游戏画面/渐变上，不遮挡内容。
  plain,
}

class AppNavBar extends StatelessWidget implements PreferredSizeWidget {
  /// 标准导航（AppBar 规范样式，对齐 RtSettingsPage 配方）。
  const AppNavBar.standard({
    super.key,
    required this.title,
    this.actions,
    this.centerTitle = false,
    this.transparent = false,
    this.backgroundColor,
    this.foregroundColor,
  })  : _kind = _AppNavBarKind.standard,
        onBack = null,
        backStyle = NavBackStyle.solid,
        backTooltip = null,
        titleSlot = null,
        centerTitleSlot = false,
        leading = null,
        floatingActions = const [],
        floatingPadding = const EdgeInsets.fromLTRB(16, 6, 16, 0),
        trailing = null,
        pillBackground = null,
        pillBorder = null,
        pillRadius = 20;

  /// 浮层行导航：放进 Stack（需要定位时自行包 `Positioned`）或 Column。
  const AppNavBar.floating({
    super.key,
    this.onBack,
    this.backStyle = NavBackStyle.solid,
    this.backTooltip,
    Widget? title,
    this.centerTitleSlot = false,
    this.leading,
    this.floatingActions = const [],
    this.floatingPadding = const EdgeInsets.fromLTRB(16, 6, 16, 0),
  })  : _kind = _AppNavBarKind.floating,
        title = null,
        titleSlot = title,
        actions = null,
        centerTitle = false,
        transparent = false,
        backgroundColor = null,
        foregroundColor = null,
        trailing = null,
        pillBackground = null,
        pillBorder = null,
        pillRadius = 20;

  /// 浮卡胶囊条导航（圆角卡；标题/trailing 为插槽）。
  const AppNavBar.pill({
    super.key,
    this.onBack,
    this.backTooltip,
    required Widget title,
    this.trailing,
    this.pillBackground,
    this.pillBorder,
    this.pillRadius = 20,
  })  : _kind = _AppNavBarKind.pill,
        titleSlot = title,
        title = null,
        actions = null,
        centerTitle = false,
        centerTitleSlot = false,
        backStyle = NavBackStyle.solid,
        leading = null,
        floatingActions = const [],
        floatingPadding = const EdgeInsets.fromLTRB(16, 6, 16, 0),
        transparent = false,
        backgroundColor = null,
        foregroundColor = null;

  final _AppNavBarKind _kind;

  // — standard —
  final String? title;
  final List<Widget>? actions;
  final bool centerTitle;
  final bool transparent;
  final Color? backgroundColor;
  final Color? foregroundColor;

  // — floating / pill —
  final VoidCallback? onBack;
  final NavBackStyle backStyle;
  final String? backTooltip;

  // — floating —
  final Widget? titleSlot;
  final bool centerTitleSlot;
  final Widget? leading;
  final List<Widget> floatingActions;
  final EdgeInsetsGeometry floatingPadding;

  // — pill —
  final Widget? trailing;
  final Color? pillBackground;
  final Color? pillBorder;
  final double pillRadius;

  @override
  Size get preferredSize {
    if (_kind == _AppNavBarKind.standard) {
      return const Size.fromHeight(kToolbarHeight);
    }
    // floating / pill 不作为 Scaffold.appBar 使用，无法静态测高；
    // 该字段仅为满足 PreferredSizeWidget 契约。
    return Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    return switch (_kind) {
      _AppNavBarKind.standard => _buildStandard(context),
      _AppNavBarKind.floating => _buildFloating(context),
      _AppNavBarKind.pill => _buildPill(context),
    };
  }

  Widget _buildStandard(BuildContext context) {
    return AppBar(
      title: title != null ? Text(title!) : null,
      centerTitle: centerTitle,
      actions: actions,
      automaticallyImplyLeading: true,
      backgroundColor: transparent
          ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.0)
          : backgroundColor,
      elevation: transparent ? 0 : null,
      foregroundColor: foregroundColor,
    );
  }

  Widget _buildFloating(BuildContext context) {
    final back = _buildBack(context);
    final hasTitle = titleSlot != null;

    if (hasTitle && centerTitleSlot) {
      // 返回/动作两端定位，标题绝对居中（focus / line 分数式）。
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: floatingPadding,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  ?back,
                  const Spacer(),
                  ...floatingActions,
                ],
              ),
              Positioned.fill(
                child: Center(child: titleSlot!),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: floatingPadding,
        child: Row(
          children: [
            ?back,
            if (hasTitle) ...[
              const SizedBox(width: 8),
              Expanded(child: titleSlot!),
            ],
            if (!hasTitle) const Spacer(),
            ...floatingActions,
          ],
        ),
      ),
    );
  }

  Widget? _buildBack(BuildContext context) {
    if (leading != null) return leading;
    if (onBack == null) return null;
    if (!context.navCanPop) return null;
    return switch (backStyle) {
      NavBackStyle.solid => BaseIconButton(
          icon: Icons.arrow_back_ios_new,
          tooltip: backTooltip ?? '返回',
          onTap: onBack,
          variant: BaseIconButtonVariant.outline,
        ),
      NavBackStyle.plain => IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          tooltip: backTooltip ?? '返回',
          onPressed: onBack,
        ),
    };
  }

  Widget _buildPill(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showBack = onBack != null && context.navCanPop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pillBackground ?? scheme.surface,
          borderRadius: BorderRadius.circular(pillRadius),
          border: pillBorder != null
              ? Border.all(color: pillBorder!, width: 1.5)
              : Border.all(color: scheme.outline.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: scheme.onSurface.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: onBack,
                  tooltip: backTooltip ?? '返回',
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              Expanded(
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: titleSlot!,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

enum _AppNavBarKind { standard, floating, pill }
