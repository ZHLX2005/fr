// 主屏：底部三 Tab 容器 + 传送带切换动画。
//
// 入口即 `_MainScreenState`：
//   - 左：ProfilePage（主页）
//   - 中：FocusHomePage（Time 心流）
//   - 右：HomePage（AI 助手）
//
// 切换用双 Transform.translate + RepaintBoundary 缓存渲染层实现"传送带"效果，
// 只移 GPU 图层不重建 widget 树，详见 fr #3 性能优化注释。

import 'package:flutter/material.dart';
import '../screens/profile/profile_page.dart';
import '../core/focus/focus_home_page.dart';
import '../screens/chat/home_page.dart';
import '../widgets/xiaodouzi_bottom_bar.dart';
import 'apk_auto_update_host.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  // RepaintBoundary 缓存渲染层，Transform 平移时只移 GPU 图层
  final List<Widget> _pages = const [
    RepaintBoundary(child: ProfilePage()),    // 主页（左）
    RepaintBoundary(child: FocusHomePage()),  // Time（中）
    RepaintBoundary(child: HomePage()),       // AI 助手（右）
  ];

  late final AnimationController _ctrl;
  late final CurvedAnimation _pageCurve;
  bool _isAnimating = false;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    // 预热 banner 路径，消除首页切换时 ProfilePage State 重建的占位帧（fr #3）
    HomeBannerCache.warmUp();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pageCurve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOutQuint,
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _selectedIndex = _toIndex;
          _isAnimating = false;
        });
        _ctrl.reset();
      }
    });
  }

  @override
  void dispose() {
    _pageCurve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex || _isAnimating) return;
    _startTransition(index);
  }

  void _onAddPressed() {
    if (_isAnimating) return;
    _startTransition(2);
  }

  void _startTransition(int target) {
    _toIndex = target;
    _isAnimating = true;
    setState(() {});
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Stack(
                children: [
                  // 底层：目标页面（静止不动）
                  SizedBox(
                    width: w,
                    child: _pages[_isAnimating ? _toIndex : _selectedIndex],
                  ),
                  // 覆盖层：双页同时平移（传送带效果）
                  if (_isAnimating)
                    AnimatedBuilder(
                      animation: _pageCurve,
                      builder: (context, _) {
                        final isForward = _toIndex > _selectedIndex;
                        final t = _pageCurve.value;
                        // 新页从异侧滑入，旧页往同侧滑出
                        final newDx = isForward ? (1 - t) * w : -(1 - t) * w;
                        final oldDx = isForward ? -t * w : t * w;
                        return SizedBox(
                          width: w,
                          child: Stack(
                            children: [
                              Transform.translate(
                                offset: Offset(newDx, 0),
                                child:
                                    SizedBox(width: w, child: _pages[_toIndex]),
                              ),
                              Transform.translate(
                                offset: Offset(oldDx, 0),
                                child: SizedBox(
                                    width: w,
                                    child: _pages[_selectedIndex]),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
          bottomNavigationBar: XiaoDouZiBottomBar(
            currentIndex: _isAnimating ? _toIndex : _selectedIndex,
            onItemSelected: _onItemTapped,
            onAddPressed: _onAddPressed,
          ),
        ),
        // 隐藏宿主：开关开启时挂载 APK 自动检查/下载触发逻辑（0x0 不可见）
        const ApkAutoUpdateMount(),
      ],
    );
  }
}