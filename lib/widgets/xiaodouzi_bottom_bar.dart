import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 底部导航数据模型
class BottomBarItem {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final bool isEnabled;

  const BottomBarItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.isEnabled = true,
  });
}

/// 小豆子底部导航栏
class XiaoDouZiBottomBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onItemSelected;
  final VoidCallback onAddPressed;

  const XiaoDouZiBottomBar({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
    required this.onAddPressed,
  });

  @override
  State<XiaoDouZiBottomBar> createState() => _XiaoDouZiBottomBarState();
}

class _XiaoDouZiBottomBarState extends State<XiaoDouZiBottomBar>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isLongPressed = false;

  // 底部导航项
  static const List<BottomBarItem> _items = [
    BottomBarItem(label: '主页', icon: Icons.home_outlined, selectedIcon: Icons.home),
    BottomBarItem(label: '聊天', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
    BottomBarItem(label: '专注', icon: Icons.radio_button_unchecked, selectedIcon: Icons.radio_button_checked, isEnabled: true), // 中间O按钮
    BottomBarItem(label: '图库', icon: Icons.photo_library_outlined, selectedIcon: Icons.photo_library),
    BottomBarItem(label: '待开发', icon: Icons.construction_outlined, isEnabled: false),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1.0, // 设置为最终状态，避免初始化时布局抖动
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: AlignmentDirectional.bottomCenter,
      children: [
        // 底部导航栏背景
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return PhysicalShape(
              color: colorScheme.surface,
              elevation: 16.0,
              clipper: _BottomBarClipper(
                radius: Tween<double>(begin: 0.0, end: 1.0)
                    .animate(CurvedAnimation(
                      parent: _animationController,
                      curve: Curves.fastOutSlowIn,
                    ))
                    .value * 38.0,
              ),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 导航项行
              SizedBox(
                height: 62,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                  child: Row(
                    children: [
                      // 主页
                      Expanded(
                        child: _buildTabItem(0, theme),
                      ),
                      // 聊天
                      Expanded(
                        child: _buildTabItem(1, theme),
                      ),
                      // 中间占位
                      SizedBox(
                        width: Tween<double>(begin: 0.0, end: 1.0)
                                .animate(CurvedAnimation(
                                  parent: _animationController,
                                  curve: Curves.fastOutSlowIn,
                                ))
                                .value *
                            64.0,
                      ),
                      // 通讯录
                      Expanded(
                        child: _buildTabItem(3, theme),
                      ),
                      // 待开发
                      Expanded(
                        child: _buildTabItem(4, theme),
                      ),
                    ],
                  ),
                ),
              ),
              // 底部安全区
              SizedBox(
                height: MediaQuery.of(context).padding.bottom,
              ),
            ],
          ),
        ),
        // 中间O按钮
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: SizedBox(
            width: 76,
            height: 76,
            child: Container(
              alignment: Alignment.topCenter,
              color: Colors.transparent,
              child: SizedBox(
                width: 76,
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ScaleTransition(
                    alignment: Alignment.center,
                    scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.fastOutSlowIn,
                      ),
                    ),
                    child: GestureDetector(
                      onTap: widget.onAddPressed,
                      onLongPressStart: (_) {
                        setState(() => _isLongPressed = true);
                        _showEasterEgg(context);
                      },
                      onLongPressEnd: (_) {
                        setState(() => _isLongPressed = false);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: widget.currentIndex == 2
                                ? [
                                    colorScheme.primary,
                                    colorScheme.tertiary,
                                  ]
                                : [
                                    colorScheme.primary,
                                    colorScheme.secondary,
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.currentIndex == 2
                                  ? colorScheme.primary.withValues(alpha: 0.6)
                                  : colorScheme.primary.withValues(alpha: 0.4),
                              offset: const Offset(4.0, 8.0),
                              blurRadius: widget.currentIndex == 2 ? 24.0 : 16.0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            width: _isLongPressed
                                ? 60
                                : (widget.currentIndex == 2 ? 40 : 0),
                            height: _isLongPressed
                                ? 60
                                : (widget.currentIndex == 2 ? 40 : 0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isLongPressed
                                  ? colorScheme.surface.withValues(alpha: 0.5)
                                  : colorScheme.surface.withValues(alpha: 0.3),
                            ),
                            child: _isLongPressed
                                ? Icon(
                                    Icons.auto_awesome,
                                    color: colorScheme.onPrimary,
                                    size: 28,
                                  )
                                : null,
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
      ],
    );
  }

  /// 显示彩蛋对话框
  void _showEasterEgg(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer,
                colorScheme.secondaryContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.tertiary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '🎉 发现了彩蛋！',
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '专注时光，让每一刻都有意义',
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.timer, size: 16),
                    label: const Text('番茄钟'),
                    backgroundColor: colorScheme.surface,
                  ),
                  Chip(
                    avatar: const Icon(Icons.spa, size: 16),
                    label: const Text('心流'),
                    backgroundColor: colorScheme.surface,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '💡 翻转手机可自动进入专注模式',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // 弹窗关闭后重置状态
      if (mounted) {
        setState(() => _isLongPressed = false);
      }
    });
  }

  Widget _buildTabItem(int index, ThemeData theme) {
    final item = _items[index];
    final isSelected = widget.currentIndex == index;
    final colorScheme = theme.colorScheme;

    // 中间专注按钮 - 特殊气泡效果
    if (index == 2) {
      return GestureDetector(
        onTap: () {
          if (!isSelected) {
            widget.onItemSelected(index);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: isSelected ? 24 : 20,
                  height: isSelected ? 24 : 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.tertiary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected ? null : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (!item.isEnabled) {
      // 待开发 - 禁用状态
      return Opacity(
        opacity: 0.4,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 24,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          widget.onItemSelected(index);
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSelected ? (item.selectedIcon ?? item.icon) : item.icon,
              size: 24,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部导航栏裁剪器 - 中间圆形缺口
class _BottomBarClipper extends CustomClipper<Path> {
  _BottomBarClipper({this.radius = 38.0});

  final double radius;

  @override
  Path getClip(Size size) {
    final Path path = Path();
    final double v = radius * 2;

    // 左上角圆角
    path.lineTo(0, 0);
    path.arcTo(
      Rect.fromLTWH(0, 0, radius, radius),
      math.pi,
      math.pi / 2,
      false,
    );

    // 中间缺口左侧
    final double leftArcStartX = (size.width / 2) - v / 2 - radius + v * 0.04;
    path.arcTo(
      Rect.fromLTWH(leftArcStartX, 0, radius, radius),
      math.pi * 1.5, // 270度
      math.pi * 0.39, // 约70度
      false,
    );

    // 中间圆形缺口
    path.arcTo(
      Rect.fromLTWH((size.width / 2) - v / 2, -v / 2, v, v),
      math.pi * 0.89, // 160度
      math.pi * -0.78, // -140度
      false,
    );

    // 中间缺口右侧
    final double rightArcStartX =
        (size.width - ((size.width / 2) - v / 2)) - v * 0.04;
    path.arcTo(
      Rect.fromLTWH(rightArcStartX, 0, radius, radius),
      math.pi * 1.11, // 200度
      math.pi * 0.39, // 约70度
      false,
    );

    // 右上角圆角
    path.arcTo(
      Rect.fromLTWH(size.width - radius, 0, radius, radius),
      math.pi * 1.5,
      math.pi / 2,
      false,
    );

    // 右下角
    path.lineTo(size.width, size.height);
    // 左下角
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(_BottomBarClipper oldClipper) => true;
}
