import 'package:flutter/material.dart';
import '../lab_container.dart';

// 颜色定义
const _kBackgroundColor = Color(0xFFF5EFEA); // 柔奶白
const _kPanelColor = Color(0xFF122E8A);     // 深海蓝
const _kWaveColor = Colors.white70;
const _kOverlayColor = Colors.black38;

// 状态枚举
enum _PullState { idle, refreshing, panelExpanded }

class PullPanelDemo extends DemoPage {
  @override
  String get title => '上拉面板';

  @override
  String get description => 'DraggableScrollableSheet上拉展开面板演示';

  @override
  Widget buildPage(BuildContext context) {
    return const PullPanelDemoPage();
  }
}

class PullPanelDemoPage extends StatefulWidget {
  const PullPanelDemoPage({super.key});

  @override
  State<PullPanelDemoPage> createState() => _PullPanelDemoPageState();
}

class _PullPanelDemoPageState extends State<PullPanelDemoPage> {
  _PullState _state = _PullState.idle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          _buildMainContent(),
          DraggableScrollableSheet(
            initialChildSize: 0.0,
            minChildSize: 0.0,
            maxChildSize: 0.9,
            snap: true,
            snapSizes: const [0.0, 0.5, 0.9],
            builder: (context, scrollController) {
              return _PullPanel(
                scrollController: scrollController,
                onStateChange: (state) => setState(() => _state = state),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_down, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('从底部向上拖拽', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('或点击按钮展开面板', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _PullPanel extends StatelessWidget {
  final ScrollController scrollController;
  final _PullState state;
  final ValueChanged<_PullState> onStateChange;

  const _PullPanel({
    required this.scrollController,
    required this.state,
    required this.onStateChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(color: _kPanelColor);
  }
}

void registerPullPanelDemo() {
  demoRegistry.register(PullPanelDemo());
}
