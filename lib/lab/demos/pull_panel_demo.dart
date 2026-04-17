import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../lab_container.dart';

const _kBackgroundColor = Color(0xFFF5EFEA);
const _kPanelColor = Color(0xFF122E8A);
const _kWaveColor = Colors.white70;

class PullPanelDemo extends DemoPage {
  @override
  String get title => '上拉面板';

  @override
  String get description => '微信式下拉面板：丝滑展开/全屏/上滑返回';

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
  // 0~1：0=收起，1=全屏面板
  double _progress = 0.0;

  // drag 过程：用于计算 velocity / 保持连续
  bool _isDragging = false;

  // 面板内部滚动控制器（全屏后用于检测是否在顶部）
  final ScrollController _panelScrollController = ScrollController();

  // snap 动画
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  // 波浪动画
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  Animation<double>? _progressAnim;

  // 刷新状态
  bool _isRefreshing = false;

  // 参数：你可以微调以接近"微信手感"
  static const double _kMainMaxPushRatio = 0.50; // 主页面最多下移 50% 屏高
  static const double _kSnapOpenThreshold = 0.60; // 松手后超过 60% 吸附到全屏
  static const double _kVelocityOpen = 900; // 向下甩开阈值
  static const double _kVelocityClose = -900; // 向上甩回阈值

  // 双阈值刷新参数
  static const double _kExpandThreshold = 0.5; // 50% 展开阈值

  @override
  void dispose() {
    _panelScrollController.dispose();
    _anim.dispose();
    _waveController.dispose();
    super.dispose();
  }

  // 将像素 drag 映射为 progress（带阻尼）
  double _applyDragToProgress({
    required double currentProgress,
    required double deltaDy,
    required double fullHeight,
  }) {
    // 目标：deltaDy >0 下拉打开；deltaDy <0 上拉关闭
    final thresholdPx = fullHeight * 0.90; // 90% 拉到全屏
    final raw = currentProgress * thresholdPx + deltaDy;

    // 阻尼：越接近全开越费劲，越接近关闭越顺滑
    double resisted = raw;
    if (raw > thresholdPx) {
      resisted = thresholdPx + (raw - thresholdPx) * 0.25;
    }
    if (raw < 0) {
      resisted = raw * 0.25;
    }

    final next = (resisted / thresholdPx).clamp(0.0, 1.0);
    return next;
  }

  void _animateTo(double target) {
    _anim.stop();
    _progressAnim?.removeListener(_onAnimTick);

    _progressAnim = Tween<double>(begin: _progress, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    )..addListener(_onAnimTick);

    _anim
      ..value = 0
      ..forward();
  }

  void _onAnimTick() {
    setState(() {
      _progress = _progressAnim!.value;
    });
  }

  // 是否认为"面板已全屏展开"
  bool get _isExpanded => _progress >= 0.999;

  // 主页是否可交互
  bool get _mainInteractive => !_isExpanded && !_isRefreshing;

  // 刷新处理（无全屏遮罩）
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    setState(() {}); // 让面板显示"虚化+三点"

    try {
      await Future.delayed(const Duration(seconds: 2));
    } finally {
      _isRefreshing = false;
      if (mounted) setState(() {});
      _animateTo(0.0); // 刷新后自动回弹
    }
  }

  // 上滑返回：滚到顶继续上滑时带走面板
  void _onPanelTopOverscroll(double overscroll) {
    if (!_isExpanded) return;
    final h = MediaQuery.of(context).size.height;
    setState(() {
      _progress = _applyDragToProgress(
        currentProgress: _progress,
        deltaDy: overscroll,
        fullHeight: h,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    // 主页面下移：0~50%（跟 progress 走一条 ease 曲线）
    final mainPush = (h * _kMainMaxPushRatio) * Curves.easeOut.transform(_progress);

    // 面板高度：0~全屏
    final panelHeight = h * Curves.easeOut.transform(_progress);

    // 面板内容是否开始可滚动：接近全屏才让它滚
    final panelScrollable = _isExpanded;

    // 文案提示
    String hint;
    if (_isRefreshing) {
      hint = '刷新中…';
    } else if (_progress < _kExpandThreshold) {
      hint = '松手刷新';
    } else if (_progress < 0.6) {
      hint = '继续下拉打开';
    } else {
      hint = '松手打开面板';
    }

    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          // 主页面（波浪在主页面上方的Stack中）
          Transform.translate(
            offset: Offset(0, mainPush),
            child: IgnorePointer(
              ignoring: !_mainInteractive,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 波浪：在主页面上方 (top: -waveH)
                  AnimatedBuilder(
                    animation: _waveController,
                    builder: (_, __) {
                      final amp = _progress > 0.15 ? 6.0 : 2.0;
                      return Positioned(
                        top: -20, // waveH = 20, 波浪在主页面上方
                        left: 0,
                        right: 0,
                        child: SizedBox(
                          height: 20,
                          child: CustomPaint(
                            painter: _WaveBeforePainter(
                              phase: _waveController.value,
                              amplitude: amp,
                              color: _kWaveColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // 主页面内容
                  _buildMainContent(),
                ],
              ),
            ),
          ),

          // 顶部面板（一直存在，只是高度变化）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: panelHeight,
            child: Stack(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(color: _kPanelColor),
                  child: _PanelContent(
                    progress: _progress,
                    scrollController: _panelScrollController,
                    scrollable: panelScrollable && !_isRefreshing,
                    hint: hint,
                    onTopOverscroll: _onPanelTopOverscroll,
                  ),
                ),
                // 刷新态 overlay：只覆盖面板区域
                if (_isRefreshing && _progress < _kExpandThreshold)
                  const Positioned.fill(
                    child: _PanelRefreshingOverlay(),
                  ),
              ],
            ),
          ),

          // 全屏手势层
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,

              onPanStart: (_) {
                if (_isRefreshing) return;
                _isDragging = true;
                _anim.stop();
              },

              onPanUpdate: (d) {
                // 面板全屏或刷新中：正常让内部滚动，不处理
                if (_isExpanded || _isRefreshing) return;

                setState(() {
                  _progress = _applyDragToProgress(
                    currentProgress: _progress,
                    deltaDy: d.delta.dy,
                    fullHeight: h,
                  );
                });
              },

              onPanEnd: (d) {
                if (_isRefreshing) return;
                _isDragging = false;

                if (_isExpanded) return;

                final vy = d.velocity.pixelsPerSecond.dy;

                // >50%：展开，<50%：刷新
                if (_progress >= _kExpandThreshold || vy > _kVelocityOpen) {
                  _animateTo(1.0);
                } else {
                  _handleRefresh();
                }
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
          Text(
            '任意位置下拉',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '面板逐渐展开 → 松手自动全屏',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          Text(
            '全屏后：滚到顶继续上滑可返回',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _PanelContent extends StatelessWidget {
  final double progress;
  final ScrollController scrollController;
  final bool scrollable;
  final String hint;
  final void Function(double overscroll) onTopOverscroll;

  const _PanelContent({
    required this.progress,
    required this.scrollController,
    required this.scrollable,
    required this.hint,
    required this.onTopOverscroll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部 handle + 标题区
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 全屏后，内容滚到顶继续上滑 -> 关闭面板
              if (!scrollable) return false;

              if (n is OverscrollNotification) {
                if (n.overscroll < 0 && scrollController.position.pixels <= 0) {
                  onTopOverscroll(n.overscroll);
                  return true; // 吃掉，避免内容 bounce
                }
              }
              return false;
            },
            child: GridView.builder(
              controller: scrollController,
              physics: scrollable
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
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

// 波浪 painter：画在分配区域的顶部，波浪线在底部
class _WaveBeforePainter extends CustomPainter {
  final double phase; // 0~1
  final double amplitude;
  final Color color;

  _WaveBeforePainter({
    required this.phase,
    required this.amplitude,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final waveH = size.height; // 20px
    final omega = 2 * math.pi;

    // 波浪线画在区域底部 (size.height - amplitude 附近)
    final baseY = waveH - amplitude - 2;

    final path = Path()..moveTo(0, waveH);

    for (double x = 0; x <= size.width; x += 1) {
      final y = baseY + amplitude * math.sin(x * 0.04 + phase * omega);
      path.lineTo(x, y);
    }

    // 封闭成一条带子填充到底部
    path
      ..lineTo(size.width, waveH)
      ..lineTo(0, waveH)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveBeforePainter oldDelegate) {
    return phase != oldDelegate.phase ||
        amplitude != oldDelegate.amplitude ||
        color != oldDelegate.color;
  }
}

class _PanelRefreshingOverlay extends StatelessWidget {
  const _PanelRefreshingOverlay();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: Colors.black.withValues(alpha: 0.10),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 56),
          child: const _TypingDots(),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget dot(double phase) {
      return AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = (_c.value + phase) % 1.0;
          final y = -6 * math.sin(t * math.pi);
          final a = 0.35 + 0.65 * math.sin(t * math.pi);
          return Opacity(
            opacity: a.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, y),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(0.0),
        const SizedBox(width: 8),
        dot(0.2),
        const SizedBox(width: 8),
        dot(0.4),
      ],
    );
  }
}

void registerPullPanelDemo() {
  demoRegistry.register(PullPanelDemo());
}
