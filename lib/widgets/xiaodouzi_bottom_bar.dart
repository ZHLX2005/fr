import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

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
  late final AnimationController _animationController;
  late final rive.FileLoader _douziFileLoader = rive.FileLoader.fromAsset(
    'assets/rive/douzi.riv',
    riveFactory: rive.Factory.rive,
  );
  bool _isLongPressed = false;

  static const List<BottomBarItem> _items = [
    BottomBarItem(
      label: '主页',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    BottomBarItem(
      label: '聊天',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
    ),
    BottomBarItem(
      label: '专注',
      icon: Icons.radio_button_unchecked,
      selectedIcon: Icons.radio_button_checked,
      isEnabled: true,
    ),
    BottomBarItem(
      label: 'LocalNet',
      icon: Icons.wifi,
      selectedIcon: Icons.wifi,
    ),
    BottomBarItem(
      label: '图库',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _douziFileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: AlignmentDirectional.bottomCenter,
      children: [
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return PhysicalShape(
              color: colorScheme.surface,
              elevation: 16.0,
              clipper: _BottomBarClipper(
                radius:
                    Tween<double>(begin: 0.0, end: 1.0)
                        .animate(
                          CurvedAnimation(
                            parent: _animationController,
                            curve: Curves.fastOutSlowIn,
                          ),
                        )
                        .value *
                    38.0,
              ),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 62,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                  child: Row(
                    children: [
                      Expanded(child: _buildTabItem(0, theme)),
                      Expanded(child: _buildTabItem(1, theme)),
                      SizedBox(
                        width:
                            Tween<double>(begin: 0.0, end: 1.0)
                                .animate(
                                  CurvedAnimation(
                                    parent: _animationController,
                                    curve: Curves.fastOutSlowIn,
                                  ),
                                )
                                .value *
                            64.0,
                      ),
                      Expanded(child: _buildTabItem(3, theme)),
                      Expanded(child: _buildTabItem(4, theme)),
                    ],
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
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
                                ? [colorScheme.primary, colorScheme.tertiary]
                                : [colorScheme.primary, colorScheme.secondary],
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
                              blurRadius: widget.currentIndex == 2
                                  ? 24.0
                                  : 16.0,
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

  void _showEasterEgg(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 316,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF9F3EA),
                Color(0xFFF1E5D6),
                Color(0xFFE8D7C5),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
              width: 1.4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A20150E),
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
              BoxShadow(
                color: Color(0x14FFFFFF),
                blurRadius: 10,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -10,
                child: IgnorePointer(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x42FFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: 36,
                child: IgnorePointer(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x22D67F54), Color(0x00D67F54)],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A261B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '人物小谱',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF2B1A12),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '看看豆子的角色设定与气质档案',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6D5648),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 248,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7EFE4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: rive.RiveWidgetBuilder(
                        fileLoader: _douziFileLoader,
                        dataBind: rive.DataBind.auto(),
                        builder: (context, state) => switch (state) {
                          rive.RiveLoading() => const SizedBox.shrink(),
                          rive.RiveFailed() => const SizedBox.shrink(),
                          rive.RiveLoaded(:final controller) => rive.RiveWidget(
                            controller: controller,
                            fit: rive.Fit.contain,
                            hitTestBehavior: rive.RiveHitTestBehavior.opaque,
                          ),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E221B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('人物小谱入口已预留'),
                          backgroundColor: colorScheme.inverseSurface,
                        ),
                      );
                    },
                    child: const Text('查看人物小谱'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isLongPressed = false);
      }
    });
  }

  Widget _buildTabItem(int index, ThemeData theme) {
    final item = _items[index];
    final isSelected = widget.currentIndex == index;
    final colorScheme = theme.colorScheme;

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
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
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
                            colors: [colorScheme.primary, colorScheme.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected
                        ? null
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
      return Opacity(
        opacity: 0.4,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 24, color: colorScheme.outline),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(fontSize: 10, color: colorScheme.outline),
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

class _BottomBarClipper extends CustomClipper<Path> {
  _BottomBarClipper({this.radius = 38.0});

  final double radius;

  @override
  Path getClip(Size size) {
    final Path path = Path();
    final double v = radius * 2;

    path.lineTo(0, 0);
    path.arcTo(
      Rect.fromLTWH(0, 0, radius, radius),
      math.pi,
      math.pi / 2,
      false,
    );

    final double leftArcStartX = (size.width / 2) - v / 2 - radius + v * 0.04;
    path.arcTo(
      Rect.fromLTWH(leftArcStartX, 0, radius, radius),
      math.pi * 1.5,
      math.pi * 0.39,
      false,
    );

    path.arcTo(
      Rect.fromLTWH((size.width / 2) - v / 2, -v / 2, v, v),
      math.pi * 0.89,
      math.pi * -0.78,
      false,
    );

    final double rightArcStartX =
        (size.width - ((size.width / 2) - v / 2)) - v * 0.04;
    path.arcTo(
      Rect.fromLTWH(rightArcStartX, 0, radius, radius),
      math.pi * 1.11,
      math.pi * 0.39,
      false,
    );

    path.arcTo(
      Rect.fromLTWH(size.width - radius, 0, radius, radius),
      math.pi * 1.5,
      math.pi / 2,
      false,
    );

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(_BottomBarClipper oldClipper) => true;
}
