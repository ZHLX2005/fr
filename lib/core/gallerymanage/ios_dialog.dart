import 'package:flutter/material.dart';

/// iOS 风格弹窗动作按钮描述。
class IosDialogAction {
  const IosDialogAction({
    required this.label,
    this.onPressed,
    this.isDestructive = false,
    this.isDefault = false,
  });

  /// 按钮文案。
  final String label;

  /// 点击回调；为 null 时呈禁用灰字态。
  final VoidCallback? onPressed;

  /// 破坏性操作（删除等），文字用 error 红。
  final bool isDestructive;

  /// 默认动作，文字加粗（iOS 系统弹窗对首选动作的处理）。
  final bool isDefault;
}

/// iOS 风格弹窗外壳：16 圆角实底卡片 + 居中文本 + hairline 分隔动作区。
///
/// 视觉规范（对齐 iOS 系统弹窗）：
/// - 标题 17 semibold 居中、正文 13.5 灰字居中；
/// - 动作区高度 44：1 个动作通栏、2 个动作左右分栏、≥3 个纵向堆叠；
/// - 破坏性动作为 error 红、默认动作加粗、禁用态灰字。
///
/// 需搭配 [showIosDialog] 使用以获得 Q 弹入场动画：
/// ```dart
/// showIosDialog(
///   context: context,
///   builder: (context) => IosDialogShell(
///     title: '标题',
///     message: '正文',
///     actions: [IosDialogAction(label: '好的', isDefault: true)],
///   ),
/// );
/// ```
class IosDialogShell extends StatelessWidget {
  const IosDialogShell({
    super.key,
    this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.maxWidth = 320,
  }) : assert(
         title != null || message != null || content != null,
         'IosDialogShell 至少需要 title / message / content 之一',
       );

  final String? title;
  final String? message;

  /// 自定义内容区（列表、加载指示器等），自带内边距。
  final Widget? content;

  final List<IosDialogAction> actions;

  /// 弹窗最大宽度；小屏时由路由的水平边距兜底。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // content 是实例字段不可类型提升，先落 local（原 ?content 空感知元素语法
    // analyzer 6.x 解析不了，见 pubspec hive_generator 注释）
    final contentWidget = content;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      // Material 供动作区 InkWell 渲染水波纹；本身透明，底色由外层 Container 负责
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || message != null) _buildHeaderText(theme),
            if (contentWidget != null) contentWidget,
            if (actions.isNotEmpty) ..._buildActionArea(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderText(ThemeData theme) {
    final hasCustomContent = content != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, hasCustomContent ? 8 : 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Text(
              title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (message != null) ...[
            if (title != null) const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 动作区：1 个动作通栏，2 个动作左右分栏，≥3 个纵向堆叠。
  List<Widget> _buildActionArea(ThemeData theme) {
    final hairline = theme.colorScheme.onSurface.withValues(alpha: 0.12);
    final divider = Container(height: 0.6, color: hairline);

    final Widget row;
    if (actions.length == 2) {
      row = Row(
        children: [
          Expanded(child: _buildActionCell(theme, actions[0])),
          Container(width: 0.6, color: hairline),
          Expanded(child: _buildActionCell(theme, actions[1])),
        ],
      );
    } else {
      row = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) divider,
            _buildActionCell(theme, actions[i]),
          ],
        ],
      );
    }
    return [divider, row];
  }

  Widget _buildActionCell(ThemeData theme, IosDialogAction action) {
    final enabled = action.onPressed != null;
    final color = !enabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.35)
        : action.isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return InkWell(
      onTap: action.onPressed,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 16,
              fontWeight: action.isDefault ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹出 iOS 风格弹窗：easeOutBack 过冲缩放（Q 弹入场）+ 快速收缩淡出退场。
Future<T?> showIosDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    _IosDialogRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
    ),
  );
}

/// 展示 iOS 风格的加载中弹窗（不可点击遮罩关闭），退场沿用原有 `Navigator.pop`。
Future<void> showIosLoadingDialog(BuildContext context, String message) {
  return showIosDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      return IosDialogShell(
        content: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _IosDialogRoute<T> extends PopupRoute<T> {
  _IosDialogRoute({
    required WidgetBuilder builder,
    required bool barrierDismissible,
  }) : _builder = builder,
       _barrierDismissible = barrierDismissible;

  static const Duration _kOpenDuration = Duration(milliseconds: 380);
  static const Duration _kCloseDuration = Duration(milliseconds: 200);

  final WidgetBuilder _builder;
  final bool _barrierDismissible;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.35);

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String? get barrierLabel => '关闭弹窗';

  @override
  Duration get transitionDuration => _kOpenDuration;

  @override
  Duration get reverseTransitionDuration => _kCloseDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: _builder(context),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 入场 scale 带 easeOutBack 过冲（峰值约 1.03，肉眼可见回弹），入场淡入只走前半程
    final scale = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.72, end: 1.0).animate(scale),
        child: child,
      ),
    );
  }
}
