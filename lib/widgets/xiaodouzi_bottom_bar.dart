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

  // 底部导航项
  static const List<BottomBarItem> _items = [
    BottomBarItem(label: '主页', icon: Icons.home_outlined, selectedIcon: Icons.home),
    BottomBarItem(label: '聊天', icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble),
    BottomBarItem(label: '专注', icon: Icons.radio_button_unchecked, isEnabled: false), // 中间O按钮
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
        // 中间添加按钮
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
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.4),
                            offset: const Offset(4.0, 8.0),
                            blurRadius: 16.0,
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          splashColor: colorScheme.onPrimary.withValues(alpha: 0.1),
                          highlightColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          onTap: widget.onAddPressed,
                          child: Text(
                            'O',
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                              letterSpacing: -2,
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
        ),
      ],
    );
  }

  Widget _buildTabItem(int index, ThemeData theme) {
    final item = _items[index];
    final isSelected = widget.currentIndex == index;
    final colorScheme = theme.colorScheme;

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
