import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 拖拽混合效果Demo
/// 使用 DraggableScrollableSheet 实现底部卡片上拖，圆角与颜色随拖拽进度渐变
class DragBlendDemo extends DemoPage {
  @override
  String get title => '拖拽混合';

  @override
  String get description => '上拖卡片产生圆角与颜色混合渐变效果';

  @override
  Widget buildPage(BuildContext context) => const _DragBlendPage();
}

class _DragBlendPage extends StatefulWidget {
  const _DragBlendPage();

  @override
  State<_DragBlendPage> createState() => _DragBlendPageState();
}

class _DragBlendPageState extends State<_DragBlendPage> {
  double _progress = 0.0;

  static const double _minExtent = 0.35;
  static const double _maxExtent = 1.0;
  static const Color _navColor = Color(0xFF6C63FF);
  static const Color _sheetColor = Colors.white;
  static const double _maxRadius = 24.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navColor,
      body: Stack(
        children: [
          // 顶部导航区
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                '探索',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(1 - _progress * 0.6),
                ),
              ),
            ),
          ),

          // 可拖拽卡片
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              setState(() {
                _progress = ((n.extent - _minExtent) / (_maxExtent - _minExtent))
                    .clamp(0.0, 1.0);
              });
              return true;
            },
            child: DraggableScrollableSheet(
              initialChildSize: _minExtent,
              minChildSize: _minExtent,
              maxChildSize: _maxExtent,
              snap: true,
              snapSizes: const [_minExtent, 0.65, _maxExtent],
              builder: (context, scrollController) {
                final radius = _maxRadius * (1 - _progress);
                final bgColor = Color.lerp(_sheetColor, _navColor, _progress)!;
                final textColor = _progress > 0.5 ? Colors.white : Colors.black87;

                return Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(radius),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1 * (1 - _progress)),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // 拖拽手柄
                      SliverToBoxAdapter(
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 12, bottom: 8),
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: textColor.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      // 卡片标题
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Text(
                            '推荐内容',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                      // 列表占位
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _navColor.withOpacity(0.15 + 0.85 * _progress),
                              child: Text('${i + 1}',
                                  style: TextStyle(color: textColor)),
                            ),
                            title: Text('Item ${i + 1}',
                                style: TextStyle(color: textColor)),
                            subtitle: Text('描述文字',
                                style: TextStyle(
                                    color: textColor.withOpacity(0.6))),
                          ),
                          childCount: 20,
                        ),
                      ),
                    ],
                  ),
                );
              },
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
