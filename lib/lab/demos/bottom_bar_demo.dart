import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../widgets/xiaodouzi_bottom_bar.dart';

class BottomBarDemo extends DemoPage {
  @override
  String get title => '底部导航条';

  @override
  String get description => 'XiaoDouZi 底部导航栏交互演示';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const _BottomBarDemoPage();
}

class _BottomBarDemoPage extends StatefulWidget {
  const _BottomBarDemoPage();

  @override
  State<_BottomBarDemoPage> createState() => _BottomBarDemoPageState();
}

class _BottomBarDemoPageState extends State<_BottomBarDemoPage> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  static const _colors = [
    Color(0xFF6C63FF),
    Color(0xFFF472B6),
    Color(0xFFFB923C),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
  ];

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

  void _onAddPressed() {
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
      bottomNavigationBar: XiaoDouZiBottomBar(
        currentIndex: _selectedIndex,
        onItemSelected: _onItemTapped,
        onAddPressed: _onAddPressed,
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
