import 'package:flutter/material.dart';

class _BarItem {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final Color color;

  const _BarItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.color = Colors.blue,
  });
}

class XiaoDouZiBottomBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onItemSelected;
  final VoidCallback? onAddPressed;

  const XiaoDouZiBottomBar({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
    this.onAddPressed,
  });

  @override
  State<XiaoDouZiBottomBar> createState() => _XiaoDouZiBottomBarState();
}

class _XiaoDouZiBottomBarState extends State<XiaoDouZiBottomBar>
    with TickerProviderStateMixin {
  static const double _indicatorSize = 52.0;
  static const double _barHeight = 62.0;

  static const List<_BarItem> _items = [
    _BarItem(
      label: '主页',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      color: Color(0xFF6C63FF),
    ),
    _BarItem(
      label: '聊天',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      color: Color(0xFFF472B6),
    ),
    _BarItem(
      label: '专注',
      icon: Icons.radio_button_unchecked,
      selectedIcon: Icons.radio_button_checked,
      color: Color(0xFFFB923C),
    ),
    _BarItem(
      label: 'LocalNet',
      icon: Icons.wifi,
      color: Color(0xFF34D399),
    ),
    _BarItem(
      label: '图库',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library,
      color: Color(0xFF60A5FA),
    ),
  ];

  late final AnimationController _slideController;
  late final CurvedAnimation _slideCurve;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..addListener(() => setState(() {}));

    _slideCurve = CurvedAnimation(
      parent: _slideController,
      curve: const Cubic(0.65, 0.0, 0.35, 1.0),
    );
  }

  @override
  void didUpdateWidget(XiaoDouZiBottomBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _previousIndex = old.currentIndex;
      _slideController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slideCurve.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final barBg = colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: MediaQuery.of(context).padding.bottom + 2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth;
          final itemWidth = contentWidth / _items.length;

          double leftFor(int idx) =>
              idx * itemWidth + (itemWidth - _indicatorSize) / 2;

          final double indicatorLeft;
          if (_slideController.isAnimating) {
            final t = _slideCurve.value;
            indicatorLeft = leftFor(_previousIndex) +
                (leftFor(widget.currentIndex) - leftFor(_previousIndex)) * t;
          } else {
            indicatorLeft = leftFor(widget.currentIndex);
          }

          return SizedBox(
            height: _barHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Tab items
                Row(
                  children: List.generate(
                    _items.length,
                    (i) => _buildTabItem(i, theme, itemWidth),
                  ),
                ),
                // Sliding indicator circle (overflows above nav bar)
                Positioned(
                  left: indicatorLeft,
                  top: -_indicatorSize / 2,
                  child: _buildIndicator(theme),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIndicator(ThemeData theme) {
    final activeItem = _items[widget.currentIndex];
    final color = activeItem.color;
    final icon = activeItem.selectedIcon ?? activeItem.icon;

    return SizedBox(
      width: _indicatorSize,
      height: _indicatorSize,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.surface.withOpacity(0.4),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildTabItem(int index, ThemeData theme, double itemWidth) {
    final item = _items[index];
    final isSelected = widget.currentIndex == index;
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => widget.onItemSelected(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: itemWidth,
        height: _barHeight,
        child: Stack(
          children: [
            // Icon — centered when inactive, moves up into indicator when active
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: const Cubic(0.34, 1.56, 0.64, 1),
              left: 0,
              right: 0,
              top: isSelected ? -4 : (_barHeight - 22) / 2,
              child: Icon(
                isSelected ? (item.selectedIcon ?? item.icon) : item.icon,
                size: 22,
                color: isSelected
                    ? item.color
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            // Label — centered, fades in when active
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isSelected ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? item.color
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
