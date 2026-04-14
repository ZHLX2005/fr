import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 主题色头部 + 白色内容区布局Demo
class DragBlendDemo extends DemoPage {
  @override
  String get title => '拖拽混合';

  @override
  String get description => 'collapsing header 效果';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const _DragBlendPage();
}

const double _kExpandedHeight = 240.0;
const double _kCollapsedHeight = kToolbarHeight;
const double _kMaxRadius = 60.0;
const double _kExpandedFontSize = 32.0;
const double _kCollapsedFontSize = 18.0;

class _DragBlendPage extends StatefulWidget {
  const _DragBlendPage();

  @override
  State<_DragBlendPage> createState() => _DragBlendPageState();
}

class _DragBlendPageState extends State<_DragBlendPage> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).colorScheme.primary;
    final t = (_scrollOffset / (_kExpandedHeight - _kCollapsedHeight)).clamp(0.0, 1.0);
    final radius = _kMaxRadius * (1 - t);
    final fontSize = _kExpandedFontSize - (_kExpandedFontSize - _kCollapsedFontSize) * t;
    final headerHeight = (_kExpandedHeight - _scrollOffset).clamp(_kCollapsedHeight, _kExpandedHeight);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 列表
          ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(top: headerHeight),
            itemCount: 30,
            itemBuilder: (context, index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: themeColor.withAlpha(31),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: themeColor, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('列表项 ${index + 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('这是第 ${index + 1} 条内容的描述信息', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                ],
              ),
            ),
          ),
          // 主题色头部 - 固定在顶部
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: (_kExpandedHeight - _scrollOffset).clamp(_kCollapsedHeight, _kExpandedHeight),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [themeColor.withAlpha(204), themeColor],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(radius),
                  bottomRight: Radius.circular(radius),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 24,
                      top: 24 + 40 * (1 - t),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: (1 - t * 2.5).clamp(0.0, 1.0),
                          child: const Text('欢迎回来 👋', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ),
                        const SizedBox(height: 4),
                        Text('我的主页', style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void registerDragBlendDemo() {
  demoRegistry.register(DragBlendDemo());
}
