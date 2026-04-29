import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: GlassBackdropScope(
          child: GlassTheme(
            data: const GlassThemeData(
              light: GlassThemeVariant(
                quality: GlassQuality.premium,
                settings: GlassThemeSettings(
                  blur: 2.5,
                  thickness: 24,
                  lightIntensity: 0.42,
                  ambientStrength: 0.06,
                  saturation: 1.10,
                ),
              ),
              dark: GlassThemeVariant(
                quality: GlassQuality.premium,
                settings: GlassThemeSettings(
                  blur: 2.5,
                  thickness: 24,
                  lightIntensity: 0.38,
                  ambientStrength: 0.06,
                  saturation: 1.08,
                ),
              ),
            ),
            child: Center(
              child: SizedBox(
                width: 292,
                height: 288,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: GlassPanel(
                        useOwnLayer: true,
                        quality: GlassQuality.premium,
                        clipBehavior: Clip.antiAlias,
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 28,
                        ),
                        padding: EdgeInsets.zero,
                        settings: const LiquidGlassSettings(
                          visibility: 0.42,
                          glassColor: Color.fromARGB(18, 255, 255, 255),
                          thickness: 30,
                          blur: 2.5,
                          lightIntensity: 0.48,
                          ambientStrength: 0.07,
                          saturation: 1.12,
                          refractiveIndex: 1.24,
                          chromaticAberration: 0.014,
                          specularSharpness: GlassSpecularSharpness.sharp,
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: SizedBox(
                        width: 252,
                        height: 248,
                        child: rive.RiveWidgetBuilder(
                          fileLoader: _douziFileLoader,
                          dataBind: rive.DataBind.auto(),
                          builder: (context, state) => switch (state) {
                            rive.RiveLoading() => const SizedBox.shrink(),
                            rive.RiveFailed() => const SizedBox.shrink(),
                            rive.RiveLoaded(:final controller) =>
                              rive.RiveWidget(
                                controller: controller,
                                fit: rive.Fit.contain,
                                hitTestBehavior:
                                    rive.RiveHitTestBehavior.opaque,
                              ),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
