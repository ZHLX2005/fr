import 'dart:math' as math;
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
  String get description => '下拉触发刷新/展开面板演示';

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

class _PullPanelDemoPageState extends State<PullPanelDemoPage>
    with SingleTickerProviderStateMixin {
  _PullState _state = _PullState.idle;
  OverlayEntry? _refreshOverlay;
  bool _isRefreshing = false;

  // 下拉相关状态
  double _dragOffset = 0.0;
  bool _isDragging = false;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  // 阈值
  static const double _refreshThreshold = 0.2; // 20% 刷新
  static const double _expandThreshold = 0.5; // 50% 展开
  static const double _hysteresis = 0.02;    // 2% 滞回，避免阈值抖动

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(vsync: this);
    _snapAnimation = _snapController.drive(Tween<double>(begin: 0, end: 0));
  }

  @override
  void dispose() {
    _refreshOverlay?.remove();
    _snapController.dispose();
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
      _snapTo(0.0);
    }
  }

  void _snapTo(double target) {
    _snapController.stop();
    _snapAnimation.removeListener(_onSnapUpdate);

    _snapAnimation = _snapController.drive(
      Tween<double>(begin: _dragOffset, end: target),
    );
    _snapController.value = 0.0;
    _snapAnimation.addListener(_onSnapUpdate);
    _snapController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onSnapUpdate() {
    setState(() {
      _dragOffset = _snapAnimation.value;
    });
  }

  void _onDragStart(DragStartDetails details) {
    // 只允许从屏幕顶部区域开始拖动
    final y = details.globalPosition.dy;
    if (y > 120) return;

    _isDragging = true;
    _snapController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final maxDrag = screenHeight * 0.9; // 最多拖到90%屏幕高度

    setState(() {
      _dragOffset += details.delta.dy;
      _dragOffset = _dragOffset.clamp(0.0, maxDrag);
    });

    // 计算下拉比例（相对于屏幕高度）
    final pullRatio = screenHeight > 0 ? _dragOffset / screenHeight : 0.0;

    // 状态判定（带滞回）
    _PullState newState;
    if (pullRatio < _refreshThreshold - _hysteresis) {
      newState = _PullState.idle;
    } else if (pullRatio < _expandThreshold - _hysteresis) {
      newState = _PullState.refreshing;
    } else {
      newState = _PullState.panelExpanded;
    }

    if (newState != _state) {
      setState(() {
        _state = newState;
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _isDragging = false;

    final screenHeight = MediaQuery.of(context).size.height;
    final pullRatio = _dragOffset / screenHeight;

    if (_state == _PullState.refreshing && !_isRefreshing) {
      // 触发刷新
      _handleRefresh();
    } else if (_state == _PullState.panelExpanded) {
      // 展开面板
      _snapTo(screenHeight * _expandThreshold);
    } else {
      // 回弹
      _snapTo(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final pullRatio = screenHeight > 0 ? _dragOffset / screenHeight : 0.0;

    // 两段式位移：前50%推主页面，后面只展开面板
    final maxPush = screenHeight * _expandThreshold;
    final pushOffset = _dragOffset.clamp(0.0, maxPush);

    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          // 主内容：跟随下拉位移向下移动（最多推50%）
          Transform.translate(
            offset: Offset(0, pushOffset),
            child: _buildMainContent(),
          ),

          // 下拉面板（从顶部展开）
          if (_dragOffset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: _isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                height: _dragOffset,
                decoration: BoxDecoration(
                  color: _kPanelColor,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: _PullDownPanel(
                  pullRatio: pullRatio,
                  state: _state,
                ),
              ),
            ),

          // 仅顶部120px区域接管手势（避免挡住面板内部网格滚动）
          if (_state != _PullState.panelExpanded && !_isRefreshing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: GestureDetector(
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
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
          Text('下拉触发刷新或展开面板',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(
            '下拉 < 20% 回弹',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          Text(
            '下拉 20% ~ 50% 刷新',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          Text(
            '下拉 > 50% 展开面板',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _PullDownPanel extends StatelessWidget {
  final double pullRatio;
  final _PullState state;

  const _PullDownPanel({
    required this.pullRatio,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 波浪分界线（下拉时激活）
        _OceanWaveDivider(isActive: pullRatio >= 0.2),

        // 拖拽指示器（纯UI，无手势）
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        // 状态提示
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            state == _PullState.refreshing
                ? '松手刷新...'
                : '松手打开面板',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ),

        // 微信小程序风格网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: _miniApps.length,
            itemBuilder: (context, index) {
              final item = _miniApps[index];
              return _MiniAppTile(item: item);
            },
          ),
        ),
      ],
    );
  }
}

// 微信小程序数据模型
class _MiniAppItem {
  final IconData icon;
  final String title;
  final Color color;
  const _MiniAppItem(this.icon, this.title, this.color);
}

const _miniApps = <_MiniAppItem>[
  _MiniAppItem(Icons.qr_code_scanner, '扫一扫', Color(0xFF4CAF50)),
  _MiniAppItem(Icons.payment, '收付款', Color(0xFF2196F3)),
  _MiniAppItem(Icons.directions_bus, '出行', Color(0xFFFF9800)),
  _MiniAppItem(Icons.shopping_bag, '购物', Color(0xFFE91E63)),
  _MiniAppItem(Icons.movie, '电影', Color(0xFF9C27B0)),
  _MiniAppItem(Icons.fastfood, '外卖', Color(0xFF00BCD4)),
  _MiniAppItem(Icons.sports_esports, '游戏', Color(0xFF795548)),
  _MiniAppItem(Icons.favorite, '健康', Color(0xFFF44336)),
];

// 微信小程序风格Tile
class _MiniAppTile extends StatelessWidget {
  final _MiniAppItem item;
  const _MiniAppTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {},
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

void registerPullPanelDemo() {
  demoRegistry.register(PullPanelDemo());
}

// ========== 海洋波浪分界线 ==========

class _OceanWavePainter extends CustomPainter {
  final double phase;      // 0~1
  final double amplitude;  // px
  final Color color;

  _OceanWavePainter({
    required this.phase,
    required this.amplitude,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final midY = size.height / 2;
    final omega = 2 * math.pi;

    path.moveTo(0, midY);

    for (double x = 0; x <= size.width; x += 1) {
      final y = midY + amplitude * math.sin(x * 0.04 + phase * omega);
      path.lineTo(x, y);
    }

    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OceanWavePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.color != color;
  }
}

class _OceanWaveDivider extends StatefulWidget {
  final bool isActive;
  const _OceanWaveDivider({required this.isActive});

  @override
  State<_OceanWaveDivider> createState() => _OceanWaveDividerState();
}

class _OceanWaveDividerState extends State<_OceanWaveDivider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _OceanWaveDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.isActive ? 20.0 : 10.0;
    final amp = widget.isActive ? 6.0 : 2.0;

    return SizedBox(
      height: h,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => CustomPaint(
          painter: _OceanWavePainter(
            phase: _controller.value,
            amplitude: amp,
            color: _kWaveColor,
          ),
        ),
      ),
    );
  }
}
