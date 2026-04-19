import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../lab_container.dart';

enum PullPanelState {
  collapsed,
  draggingMain,
  draggingPanel,
  settling,
  expanded,
  refreshing,
}

enum PullPanelActionType { none, animateTo, startRefresh }

class PullPanelAction {
  final PullPanelActionType type;
  final double? targetProgress;

  const PullPanelAction._(this.type, {this.targetProgress});

  const PullPanelAction.none() : this._(PullPanelActionType.none);

  const PullPanelAction.animateTo(double target)
    : this._(PullPanelActionType.animateTo, targetProgress: target);

  const PullPanelAction.startRefresh()
    : this._(PullPanelActionType.startRefresh);
}

class PullPanelMetrics {
  static const double refreshThreshold = 0.125;
  static const double hintOpenThreshold = 0.15;
  static const double closeSnapThreshold = 0.90;
  static const double velocityOpen = 900;
  static const double dragDamping = 0.18;
  static const double overdragResistance = 0.04;
  static const double mainPushRatio = 0.50;

  const PullPanelMetrics._();

  static double applyDrag({
    required double currentProgress,
    required double deltaDy,
    required double fullHeight,
  }) {
    final panelRangePx = fullHeight;
    final dampedDelta = deltaDy * dragDamping;
    final raw = currentProgress * panelRangePx + dampedDelta;

    double resisted = raw;
    if (raw > panelRangePx) {
      resisted = panelRangePx + (raw - panelRangePx) * overdragResistance;
    } else if (raw < 0) {
      resisted = raw * overdragResistance;
    }

    return (resisted / panelRangePx).clamp(0.0, 1.0);
  }
}

class PullPanelStateMachine {
  PullPanelState _state = PullPanelState.collapsed;
  double _progress = 0.0;

  PullPanelState get state => _state;
  double get progress => _progress;

  bool get mainInteractive =>
      _state == PullPanelState.collapsed ||
      _state == PullPanelState.draggingMain;

  bool get panelScrollable =>
      _state == PullPanelState.expanded ||
      _state == PullPanelState.draggingPanel;

  bool get showRefreshOverlay =>
      _state == PullPanelState.refreshing &&
      _progress < PullPanelMetrics.refreshThreshold;

  String get hintText {
    if (_state == PullPanelState.refreshing) return 'Refreshing...';
    if (_progress < PullPanelMetrics.refreshThreshold) {
      return 'Pull down to refresh';
    }
    if (_progress < PullPanelMetrics.hintOpenThreshold) {
      return 'Release to refresh';
    }
    return 'Release to open panel';
  }

  void syncProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
  }

  void beginMainDrag() {
    if (_state == PullPanelState.refreshing) return;
    _state = PullPanelState.draggingMain;
  }

  void updateMainDrag({required double deltaDy, required double fullHeight}) {
    if (_state != PullPanelState.draggingMain) return;
    _progress = PullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: deltaDy,
      fullHeight: fullHeight,
    );
  }

  PullPanelAction endMainDrag({required double velocityDy}) {
    if (_state != PullPanelState.draggingMain) {
      return const PullPanelAction.none();
    }

    final shouldOpen =
        _progress >= PullPanelMetrics.refreshThreshold ||
        velocityDy > PullPanelMetrics.velocityOpen;
    if (shouldOpen) {
      _state = PullPanelState.settling;
      return const PullPanelAction.animateTo(1.0);
    }

    _state = PullPanelState.refreshing;
    return const PullPanelAction.startRefresh();
  }

  void absorbPanelOverscroll({
    required double overscrollDy,
    required double fullHeight,
  }) {
    if (_state != PullPanelState.expanded &&
        _state != PullPanelState.draggingPanel) {
      return;
    }

    _state = PullPanelState.draggingPanel;
    _progress = PullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: overscrollDy,
      fullHeight: fullHeight,
    );
  }

  PullPanelAction endPanelDrag() {
    if (_state != PullPanelState.draggingPanel) {
      return const PullPanelAction.none();
    }

    _state = PullPanelState.settling;
    final shouldClose = _progress < PullPanelMetrics.closeSnapThreshold;
    return PullPanelAction.animateTo(shouldClose ? 0.0 : 1.0);
  }

  void onAnimationStarted() {
    _state = PullPanelState.settling;
  }

  void onAnimationCompleted(double targetProgress) {
    _progress = targetProgress.clamp(0.0, 1.0);
    if (_progress <= 0.0) {
      _state = PullPanelState.collapsed;
    } else if (_progress >= 1.0) {
      _state = PullPanelState.expanded;
    } else {
      _state = PullPanelState.collapsed;
    }
  }

  void onRefreshFinished() {
    if (_state == PullPanelState.refreshing) {
      _state = PullPanelState.collapsed;
    }
  }
}

const _kBackgroundColor = Color(0xFFF5EFEA);
const _kPanelColor = Color(0xFF122E8A);
const _kWaveColor = Colors.white70;
const _kAnimationDuration = Duration(milliseconds: 260);
const _kRefreshDuration = Duration(seconds: 2);
const _kWaveDuration = Duration(seconds: 2);

class PullPanelDemo extends DemoPage {
  @override
  String get title => 'Pull Panel';

  @override
  String get description =>
      'Deterministic pull-to-refresh and full-screen panel demo';

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
    with TickerProviderStateMixin {
  final PullPanelStateMachine _sm = PullPanelStateMachine();
  final ScrollController _panelScrollController = ScrollController();

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: _kAnimationDuration,
  )..addStatusListener(_onAnimationStatusChanged);

  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: _kWaveDuration,
  )..repeat();

  Animation<double>? _progressAnim;
  double? _pendingAnimationTarget;

  double get _progress => _sm.progress;
  bool get _isRefreshing => _sm.state == PullPanelState.refreshing;

  @override
  void dispose() {
    _progressAnim?.removeListener(_onAnimTick);
    _panelScrollController.dispose();
    _anim.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _stopCurrentAnimation() {
    if (_anim.isAnimating) {
      _anim.stop();
    }
    _progressAnim?.removeListener(_onAnimTick);
    _progressAnim = null;
    _pendingAnimationTarget = null;
    _sm.syncProgress(_progress);
  }

  void _animateTo(double target) {
    _stopCurrentAnimation();
    _pendingAnimationTarget = target;
    _sm.onAnimationStarted();

    _progressAnim = Tween<double>(begin: _progress, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    )..addListener(_onAnimTick);

    setState(() {});
    _anim.forward(from: 0.0);
  }

  void _onAnimTick() {
    final animation = _progressAnim;
    if (animation == null) return;
    _sm.syncProgress(animation.value);
    if (mounted) {
      setState(() {});
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    final target = _pendingAnimationTarget;
    if (target == null) return;

    _progressAnim?.removeListener(_onAnimTick);
    _progressAnim = null;
    _pendingAnimationTarget = null;
    _sm.onAnimationCompleted(target);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    setState(() {});
    try {
      await Future.delayed(_kRefreshDuration);
    } finally {
      if (mounted) {
        if (_panelScrollController.hasClients) {
          _panelScrollController.jumpTo(0.0);
        }
        _sm.onRefreshFinished();
        _animateTo(0.0);
      }
    }
  }

  void _runAction(PullPanelAction action) {
    switch (action.type) {
      case PullPanelActionType.none:
        setState(() {});
      case PullPanelActionType.animateTo:
        _animateTo(action.targetProgress!);
      case PullPanelActionType.startRefresh:
        _handleRefresh();
    }
  }

  void _onMainPanStart() {
    _stopCurrentAnimation();
    _sm.beginMainDrag();
    setState(() {});
  }

  void _onMainPanUpdate(double deltaDy, double fullHeight) {
    if (_anim.isAnimating) return;
    _sm.updateMainDrag(deltaDy: deltaDy, fullHeight: fullHeight);
    setState(() {});
  }

  void _onMainPanEnd(double velocityDy) {
    _runAction(_sm.endMainDrag(velocityDy: velocityDy));
  }

  void _onPanelTopOverscroll(double overscroll, double fullHeight) {
    if (_isRefreshing) return;

    _sm.absorbPanelOverscroll(overscrollDy: overscroll, fullHeight: fullHeight);
    setState(() {});
  }

  void _onPanelScrollEnd() {
    _runAction(_sm.endPanelDrag());
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final mainPush = screenHeight * PullPanelMetrics.mainPushRatio * _progress;
    final panelHeight = screenHeight * _progress;

    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          Transform.translate(
            offset: Offset(0, mainPush),
            child: IgnorePointer(
              ignoring: !_sm.mainInteractive,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -20,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 20,
                      child: AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          final amplitude = _progress > 0.15 ? 6.0 : 2.0;
                          return CustomPaint(
                            painter: _WaveBeforePainter(
                              phase: _waveController.value,
                              amplitude: amplitude,
                              color: _kWaveColor,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  _buildMainContent(),
                ],
              ),
            ),
          ),
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
                    scrollController: _panelScrollController,
                    scrollable: _sm.panelScrollable && !_isRefreshing,
                    hint: _sm.hintText,
                    onTopOverscroll: (overscroll) {
                      _onPanelTopOverscroll(overscroll, screenHeight);
                    },
                    onPanelScrollEnd: _onPanelScrollEnd,
                  ),
                ),
                if (_sm.showRefreshOverlay)
                  const Positioned.fill(child: _PanelRefreshingOverlay()),
              ],
            ),
          ),
          if (_sm.mainInteractive && !_isRefreshing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => _onMainPanStart(),
                onPanUpdate: (details) {
                  _onMainPanUpdate(details.delta.dy, screenHeight);
                },
                onPanEnd: (details) {
                  _onMainPanEnd(details.velocity.pixelsPerSecond.dy);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    final textColor = Colors.grey.shade600;
    final secondaryTextColor = Colors.grey.shade500;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_down, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Pull from anywhere',
            style: TextStyle(fontSize: 18, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Drag to expand, release to open',
            style: TextStyle(fontSize: 14, color: secondaryTextColor),
          ),
          Text(
            'At the top, overscroll upward to close',
            style: TextStyle(fontSize: 14, color: secondaryTextColor),
          ),
        ],
      ),
    );
  }
}

class _PanelContent extends StatelessWidget {
  final ScrollController scrollController;
  final bool scrollable;
  final String hint;
  final ValueChanged<double> onTopOverscroll;
  final VoidCallback onPanelScrollEnd;

  const _PanelContent({
    required this.scrollController,
    required this.scrollable,
    required this.hint,
    required this.onTopOverscroll,
    required this.onPanelScrollEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
          child: IgnorePointer(
            ignoring: !scrollable,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (!scrollable) return false;
                if (!scrollController.hasClients) return false;

                final position = scrollController.position;
                final atTop = position.pixels <= position.minScrollExtent;

                if (notification is OverscrollNotification &&
                    atTop &&
                    notification.overscroll < 0) {
                  onTopOverscroll(notification.overscroll);
                  return true;
                }

                if (notification is ScrollEndNotification) {
                  onPanelScrollEnd();
                }

                return false;
              },
              child: GridView.builder(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: 40,
                itemBuilder: (context, index) {
                  final item = _miniApps[index % _miniApps.length];
                  return _MiniAppTile(item: item);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniAppItem {
  final IconData icon;
  final String title;
  final Color color;

  const _MiniAppItem(this.icon, this.title, this.color);
}

const _miniApps = <_MiniAppItem>[
  _MiniAppItem(Icons.qr_code_scanner, 'Scan', Color(0xFF4CAF50)),
  _MiniAppItem(Icons.payment, 'Pay', Color(0xFF2196F3)),
  _MiniAppItem(Icons.directions_bus, 'Travel', Color(0xFFFF9800)),
  _MiniAppItem(Icons.shopping_bag, 'Shop', Color(0xFFE91E63)),
  _MiniAppItem(Icons.movie, 'Movie', Color(0xFF9C27B0)),
  _MiniAppItem(Icons.fastfood, 'Food', Color(0xFF00BCD4)),
  _MiniAppItem(Icons.sports_esports, 'Games', Color(0xFF795548)),
  _MiniAppItem(Icons.favorite, 'Health', Color(0xFFF44336)),
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

class _WaveBeforePainter extends CustomPainter {
  final double phase;
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

    final waveHeight = size.height;
    final omega = 2 * math.pi;
    final baseY = waveHeight - amplitude - 2;

    final path = Path()..moveTo(0, waveHeight);

    for (double x = 0; x <= size.width; x += 1) {
      final y = baseY + amplitude * math.sin(x * 0.04 + phase * omega);
      path.lineTo(x, y);
    }

    path
      ..lineTo(size.width, waveHeight)
      ..lineTo(0, waveHeight)
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
        builder: (context, child) {
          final t = (_c.value + phase) % 1.0;
          final y = -6 * math.sin(t * math.pi);
          final opacity = 0.35 + 0.65 * math.sin(t * math.pi);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, y), child: child),
          );
        },
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
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
