import 'package:flutter/material.dart';
import '../lab_container.dart';

class BottomBarDemo extends DemoPage {
  @override
  String get title => '底部导航条';

  @override
  String get slug => 'bottom-bar';

  @override
  String get description => 'XiaoDouZi 底部导航栏交互演示';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const _BottomBarDemoPage();
}

// ═══════════════════════════════════════════
// 旧版 5-tab 底部导航条（demo 专用，不依赖共享组件）
// ═══════════════════════════════════════════

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

class _LegacyBottomBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onItemSelected;

  const _LegacyBottomBar({
    required this.currentIndex,
    required this.onItemSelected,
  });

  @override
  State<_LegacyBottomBar> createState() => _LegacyBottomBarState();
}

class _LegacyBottomBarState extends State<_LegacyBottomBar>
    with TickerProviderStateMixin {
  static const double _indicatorSize = 52.0;
  static const double _barHeight = 68.0;
  static const Color _navBg = Color(0xFFFFFFFF);

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
      label: 'Game',
      icon: Icons.sports_esports,
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
  void didUpdateWidget(_LegacyBottomBar old) {
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
    final pageBg = colorScheme.surface;

    return Container(
      decoration: const BoxDecoration(
        color: _navBg,
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: MediaQuery.of(context).padding.bottom + 2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / _items.length;

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
                Positioned(
                  left: indicatorLeft,
                  top: -_indicatorSize / 2,
                  child: _buildIndicator(theme, pageBg),
                ),
                Row(
                  children: List.generate(
                    _items.length,
                    (i) => _buildTabItem(i, theme, itemWidth),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIndicator(ThemeData theme, Color pageBg) {
    final color = theme.colorScheme.primary;

    return SizedBox(
      width: _indicatorSize,
      height: _indicatorSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -14.5,
            top: 26,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _navBg,
                borderRadius:
                    const BorderRadius.only(topRight: Radius.circular(10)),
                boxShadow: [
                  BoxShadow(
                    color: pageBg,
                    offset: const Offset(0, -6),
                    blurRadius: 0,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: -14.5,
            top: 26,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _navBg,
                borderRadius:
                    const BorderRadius.only(topLeft: Radius.circular(10)),
                boxShadow: [
                  BoxShadow(
                    color: pageBg,
                    offset: const Offset(0, -6),
                    blurRadius: 0,
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: pageBg, width: 4),
            ),
          ),
        ],
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
          clipBehavior: Clip.none,
          children: [
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isSelected ? 1.0 : 0.0,
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: (_barHeight - 22) / 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: const Cubic(0.34, 1.56, 0.64, 1),
                transform: Matrix4.translationValues(
                  0,
                  isSelected ? -34.0 : 0.0,
                  0,
                ),
                transformAlignment: Alignment.center,
                child: Icon(
                  isSelected ? (item.selectedIcon ?? item.icon) : item.icon,
                  size: 22,
                  color:
                      isSelected ? Colors.white : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// Demo 页面
// ═══════════════════════════════════════════

class _BottomBarDemoPage extends StatefulWidget {
  const _BottomBarDemoPage();

  @override
  State<_BottomBarDemoPage> createState() => _BottomBarDemoPageState();
}

class _BottomBarDemoPageState extends State<_BottomBarDemoPage> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  static const _titles = [
    '主页',
    '聊天',
    '专注',
    'Game',
    '图库',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
  }

  void _onItemTapped(int index) {
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: _onPageChanged,
        children: List.generate(5, (i) => _buildPage(i)),
      ),
      bottomNavigationBar: _LegacyBottomBar(
        currentIndex: _selectedIndex,
        onItemSelected: _onItemTapped,
      ),
    );
  }

  Widget _buildPage(int index) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 80,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 24),
            Text(
              _titles[index],
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '当前选中',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void registerBottomBarDemo() {
  demoRegistry.register(BottomBarDemo());
}
