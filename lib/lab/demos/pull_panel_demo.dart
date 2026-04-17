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
  OverlayEntry? _refreshOverlay;
  bool _isRefreshing = false;

  @override
  void dispose() {
    _refreshOverlay?.remove();
    super.dispose();
  }

  void _showRefreshOverlay() {
    _refreshOverlay?.remove();
    _refreshOverlay = OverlayEntry(
      builder: (context) => Container(
        color: _kOverlayColor,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
    Overlay.of(context).insert(_refreshOverlay!);
  }

  void _hideRefreshOverlay() {
    _refreshOverlay?.remove();
    _refreshOverlay = null;
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _showRefreshOverlay();
    try {
      await Future.delayed(const Duration(seconds: 3));
    } finally {
      _isRefreshing = false;
      _hideRefreshOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          _buildMainContent(),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              final sheetSize = notification.extent / 0.9; // 转换为实际屏幕占比 0.0~1.0
              final prevState = _state;

              if (sheetSize < 0.2) {
                _state = _PullState.idle;
              } else if (sheetSize < 0.5) {
                if (_state != _PullState.refreshing) {
                  _state = _PullState.refreshing;
                  _handleRefresh(); // 触发刷新
                }
              } else {
                _state = _PullState.panelExpanded;
              }

              if (prevState != _state) {
                setState(() {});
              }
              return true;
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.0,
              minChildSize: 0.0,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.0, 0.5, 0.9],
              builder: (context, scrollController) {
                return _PullPanel(
                  scrollController: scrollController,
                  state: _state,
                  onStateChange: (state) => setState(() => _state = state),
                );
              },
            ),
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

class _OceanWavePainter extends CustomPainter {
  final double phase;      // 动画相位 0.0~1.0
  final double amplitude;  // 波浪幅度
  final bool isActive;     // 是否激活动画

  _OceanWavePainter({
    required this.phase,
    required this.amplitude,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kWaveColor
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x += 1) {
      final waveY = isActive
          ? size.height / 2 + amplitude * _sin(x * 0.04 + phase * 2 * 3.14159)
          : size.height / 2;
      path.lineTo(x, waveY);
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  double _sin(double x) => (x - (x * x * x) / 6 + (x * x * x * x * x) / 120).clamp(-1.0, 1.0);

  @override
  bool shouldRepaint(_OceanWavePainter oldDelegate) =>
      phase != oldDelegate.phase || amplitude != oldDelegate.amplitude || isActive != oldDelegate.isActive;
}

class _OceanWaveDivider extends StatefulWidget {
  final bool isActive;

  const _OceanWaveDivider({required this.isActive});

  @override
  State<_OceanWaveDivider> createState() => _OceanWaveDividerState();
}

class _OceanWaveDividerState extends State<_OceanWaveDivider> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, widget.isActive ? 20 : 8),
          painter: _OceanWavePainter(
            phase: _controller.value,
            amplitude: widget.isActive ? 6.0 : 2.0,
            isActive: widget.isActive,
          ),
        );
      },
    );
  }
}

void registerPullPanelDemo() {
  demoRegistry.register(PullPanelDemo());
}
