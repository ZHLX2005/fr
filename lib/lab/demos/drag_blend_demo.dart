import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 主题色头部 + 白色内容区布局Demo
class DragBlendDemo extends DemoPage {
  @override
  String get title => '拖拽混合';

  @override
  String get description => 'collapsing header 效果';

  @override
  Widget buildPage(BuildContext context) => const _DragBlendPage();
}

const double _kExpandedHeight = 240.0;
const double _kMaxRadius = 60.0;
const double _kExpandedFontSize = 32.0;
const double _kCollapsedFontSize = 18.0;

class _DragBlendPage extends StatelessWidget {
  const _DragBlendPage();

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: false,
            delegate: _CollapsingHeaderDelegate(
              expandedHeight: _kExpandedHeight,
              maxRadius: _kMaxRadius,
              expandedFontSize: _kExpandedFontSize,
              collapsedFontSize: _kCollapsedFontSize,
              themeColor: themeColor,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: themeColor.withAlpha(31),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(color: themeColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('列表项 ${index + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text('这是第 ${index + 1} 条内容的描述信息', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  ],
                ),
              ),
              childCount: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double maxRadius;
  final double expandedFontSize;
  final double collapsedFontSize;
  final Color themeColor;

  _CollapsingHeaderDelegate({
    required this.expandedHeight,
    required this.maxRadius,
    required this.expandedFontSize,
    required this.collapsedFontSize,
    required this.themeColor,
  });

  @override
  double get maxExtent => expandedHeight;

  @override
  double get minExtent => 0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / maxExtent).clamp(0.0, 1.0);
    final radius = maxRadius * (1 - t);
    final fontSize = expandedFontSize - (expandedFontSize - collapsedFontSize) * t;

    return SizedBox(
      height: expandedHeight - shrinkOffset,
      child: Stack(
        children: [
          // 主题色背景块 - 只有渐变，没有 color
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: expandedHeight - shrinkOffset,
            child: Container(
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
            ),
          ),
          // 标题内容
          SafeArea(
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
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingHeaderDelegate oldDelegate) => true;
}

void registerDragBlendDemo() {
  demoRegistry.register(DragBlendDemo());
}
