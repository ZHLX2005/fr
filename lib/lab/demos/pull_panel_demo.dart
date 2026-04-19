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
  static const double mainDragDeadZone = 8.0;
  static const double collapsedEpsilon = 0.001;
  static const double refreshThreshold = 0.125;
  static const double hintOpenThreshold = 0.15;
  static const double closeSnapThreshold = 0.90;
  static const double velocityOpen = 900;
  static const double dragDamping = 0.25;
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
  double _pendingMainDragDy = 0.0;

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

  double get refreshProgress =>
      (_progress / PullPanelMetrics.refreshThreshold).clamp(0.0, 1.0);

  bool get readyToOpen => _progress >= PullPanelMetrics.hintOpenThreshold;

  bool get readyToRefresh =>
      _progress >= PullPanelMetrics.refreshThreshold && !readyToOpen;

  bool get showMainCue =>
      _state == PullPanelState.collapsed ||
      _state == PullPanelState.draggingMain;

  bool get showCloseCue =>
      _state == PullPanelState.expanded ||
      _state == PullPanelState.draggingPanel;

  double get closeProgress {
    if (_progress >= 1.0) return 0.0;
    return ((1.0 - _progress) / (1.0 - PullPanelMetrics.closeSnapThreshold))
        .clamp(0.0, 1.0);
  }

  void syncProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
    if (_progress <= 0.0 &&
        _state != PullPanelState.refreshing &&
        _state != PullPanelState.settling) {
      _state = PullPanelState.collapsed;
    }
  }

  void beginMainDrag() {
    if (_state == PullPanelState.refreshing ||
        _state == PullPanelState.settling ||
        _state == PullPanelState.expanded ||
        _state == PullPanelState.draggingPanel) {
      return;
    }
    _pendingMainDragDy = 0.0;
  }

  void updateMainDrag({required double deltaDy, required double fullHeight}) {
    var effectiveDeltaDy = deltaDy;

    if (_state != PullPanelState.draggingMain) {
      _pendingMainDragDy += effectiveDeltaDy;

      final passedDeadZone =
          _pendingMainDragDy.abs() >= PullPanelMetrics.mainDragDeadZone;
      if (!passedDeadZone) return;

      if (_pendingMainDragDy <= 0) {
        _pendingMainDragDy = 0.0;
        return;
      }

      _state = PullPanelState.draggingMain;
      effectiveDeltaDy = _pendingMainDragDy;
      _pendingMainDragDy = 0.0;
    }

    _progress = PullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: effectiveDeltaDy,
      fullHeight: fullHeight,
    );
  }

  PullPanelAction endMainDrag({required double velocityDy}) {
    if (_state != PullPanelState.draggingMain) {
      _pendingMainDragDy = 0.0;
      if (_progress <= PullPanelMetrics.collapsedEpsilon) {
        _progress = 0.0;
        _state = PullPanelState.collapsed;
      }
      return const PullPanelAction.none();
    }

    _pendingMainDragDy = 0.0;

    if (_progress <= PullPanelMetrics.collapsedEpsilon) {
      _progress = 0.0;
      _state = PullPanelState.collapsed;
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
    _pendingMainDragDy = 0.0;
    _state = PullPanelState.settling;
  }

  void onAnimationCompleted(double targetProgress) {
    _pendingMainDragDy = 0.0;
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
    _pendingMainDragDy = 0.0;
    if (_state == PullPanelState.refreshing) {
      _state = PullPanelState.collapsed;
    }
  }
}

const _kBackgroundColor = Color(0xFFF5EFEA);
const _kPanelGradientTop = Color(0xFFF8F3EE);
const _kPanelGradientMiddle = Color(0xFFEFE6DD);
const _kPanelGradientBottom = Color(0xFFE4D6C8);
const _kPanelBorderColor = Color(0x59FFFFFF);
const _kWaveColor = Color(0xE6FFF9F4);
const _kAccentColor = Color(0xFFC88A5A);
const _kAccentSoftColor = Color(0xFFD9A97C);
const _kAccentDeepColor = Color(0xFF8B5E3C);
const _kPanelTextColor = Color(0xFF5E4735);
const _kPanelMutedTextColor = Color(0xFF8E7561);
const _kCardBaseColor = Color(0xF2FFFCF8);
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
  bool _refreshInFlight = false;

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
    if (_refreshInFlight) return;

    _refreshInFlight = true;
    setState(() {});
    try {
      await Future.delayed(_kRefreshDuration);
    } finally {
      _refreshInFlight = false;
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
    final mainScale = 1.0 - (_progress * 0.02);

    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          Transform.translate(
            offset: Offset(0, mainPush),
            child: Transform.scale(
              scale: mainScale,
              alignment: Alignment.topCenter,
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
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: panelHeight,
            child: Stack(
              children: [
                ClipRect(
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _kPanelGradientTop,
                                _kPanelGradientMiddle,
                                _kPanelGradientBottom,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PanelSurfacePainter(progress: _progress),
                        ),
                      ),
                      _PanelContent(
                        scrollController: _panelScrollController,
                        scrollable: _sm.panelScrollable && !_isRefreshing,
                        progress: _progress,
                        refreshProgress: _sm.refreshProgress,
                        readyToRefresh: _sm.readyToRefresh,
                        readyToOpen: _sm.readyToOpen,
                        refreshing: _isRefreshing,
                        closeProgress: _sm.closeProgress,
                        showCloseCue: _sm.showCloseCue,
                        onTopOverscroll: (overscroll) {
                          _onPanelTopOverscroll(overscroll, screenHeight);
                        },
                        onPanelScrollEnd: _onPanelScrollEnd,
                      ),
                    ],
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _MainPullCue(
            progress: _progress,
            phase: _waveController.value,
            visible: _sm.showMainCue && !_isRefreshing,
          ),
        ],
      ),
    );
  }
}

class _PanelContent extends StatelessWidget {
  final ScrollController scrollController;
  final bool scrollable;
  final double progress;
  final double refreshProgress;
  final bool readyToRefresh;
  final bool readyToOpen;
  final bool refreshing;
  final double closeProgress;
  final bool showCloseCue;
  final ValueChanged<double> onTopOverscroll;
  final VoidCallback onPanelScrollEnd;

  const _PanelContent({
    required this.scrollController,
    required this.scrollable,
    required this.progress,
    required this.refreshProgress,
    required this.readyToRefresh,
    required this.readyToOpen,
    required this.refreshing,
    required this.closeProgress,
    required this.showCloseCue,
    required this.onTopOverscroll,
    required this.onPanelScrollEnd,
  });

  @override
  Widget build(BuildContext context) {
    final contentBlur = ((1.0 - progress) * 16.0).clamp(0.0, 16.0);
    final contentOverlayOpacity = ((1.0 - progress) * 0.18).clamp(0.0, 0.18);
    final contentOffset = (1.0 - progress) * 16.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          child: _PanelHandle(
            progress: progress,
            refreshProgress: refreshProgress,
            readyToRefresh: readyToRefresh,
            readyToOpen: readyToOpen,
            refreshing: refreshing,
            closeProgress: closeProgress,
            showCloseCue: showCloseCue,
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: contentBlur,
                    sigmaY: contentBlur,
                  ),
                  child: IgnorePointer(
                    ignoring: !scrollable,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (!scrollable) return false;
                        if (!scrollController.hasClients) return false;

                        final position = scrollController.position;
                        final atTop =
                            position.pixels <= position.minScrollExtent;

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
                      child: Transform.translate(
                        offset: Offset(0, contentOffset),
                        child: ListView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
                          children: const [
                            _PanelHeroSection(),
                            SizedBox(height: 18),
                            _PanelSectionHeader(
                              eyebrow: 'CURATED',
                              title: 'Soft focus essentials',
                            ),
                            SizedBox(height: 12),
                            _PanelFeatureGrid(),
                            SizedBox(height: 18),
                            _PanelSectionHeader(
                              eyebrow: 'QUICK STRIPS',
                              title: 'Small actions, warm materials',
                            ),
                            SizedBox(height: 12),
                            _PanelActionChips(),
                            SizedBox(height: 18),
                            _PanelSectionHeader(
                              eyebrow: 'AMBIENCE',
                              title: 'A few slower, richer cards',
                            ),
                            SizedBox(height: 12),
                            _PanelStoryRail(),
                            SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: contentOverlayOpacity),
                        Colors.white.withValues(
                          alpha: contentOverlayOpacity * 0.35,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;

  const _PanelSectionHeader({required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: _kAccentDeepColor,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: _kPanelTextColor,
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeroSection extends StatelessWidget {
  const _PanelHeroSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(
          flex: 6,
          child: _FeatureCard(
            icon: Icons.wb_twilight_rounded,
            title: 'Morning glow',
            subtitle:
                'Soft lighting, calm surfaces, a sheet that feels poured.',
            accent: Color(0xFFD9A97C),
            height: 208,
            large: true,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _FeatureCard(
                icon: Icons.spa_rounded,
                title: 'Ritual',
                subtitle: 'Gentle pace',
                accent: Color(0xFFC8A7A1),
                height: 98,
              ),
              SizedBox(height: 12),
              _FeatureCard(
                icon: Icons.auto_awesome_rounded,
                title: 'Polish',
                subtitle: 'Warm glass',
                accent: Color(0xFFC9AE7B),
                height: 98,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelFeatureGrid extends StatelessWidget {
  const _PanelFeatureGrid();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _FeatureCard(
                icon: Icons.self_improvement_rounded,
                title: 'Quiet Mode',
                subtitle: 'Lower contrast and ease every edge.',
                accent: Color(0xFF9CAF88),
                height: 132,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                icon: Icons.local_cafe_rounded,
                title: 'Pause',
                subtitle: 'Cream, cinnamon, daylight.',
                accent: Color(0xFFD79B74),
                height: 132,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: _FeatureCard(
                icon: Icons.texture_rounded,
                title: 'Materials',
                subtitle: 'Paper grain, frosted glass and quiet highlights.',
                accent: Color(0xFF9AA8B5),
                height: 120,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: _FeatureCard(
                icon: Icons.favorite_outline_rounded,
                title: 'Care',
                subtitle: 'Low-saturation warmth.',
                accent: Color(0xFFC8A7A1),
                height: 120,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PanelActionChips extends StatelessWidget {
  const _PanelActionChips();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: const [
        _ActionChip(icon: Icons.tune_rounded, label: 'Filter'),
        _ActionChip(icon: Icons.palette_outlined, label: 'Palette'),
        _ActionChip(icon: Icons.air_rounded, label: 'Mist'),
        _ActionChip(icon: Icons.waves_rounded, label: 'Flow'),
        _ActionChip(icon: Icons.brightness_5_outlined, label: 'Glow'),
        _ActionChip(icon: Icons.view_quilt_outlined, label: 'Layout'),
      ],
    );
  }
}

class _PanelStoryRail extends StatelessWidget {
  const _PanelStoryRail();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _StoryCard(
          icon: Icons.layers_outlined,
          title: 'Layered sheet',
          body:
              'The surface reads as one continuous cream-glass plane, not a hard drawer.',
        ),
        SizedBox(height: 12),
        _StoryCard(
          icon: Icons.blur_on_rounded,
          title: 'Blur to focus',
          body:
              'Content enters as haze, then sharpens as the panel settles into place.',
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final double height;
  final bool large;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.height,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.all(large ? 18 : 16),
      decoration: BoxDecoration(
        color: _kCardBaseColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kPanelBorderColor),
        boxShadow: [
          BoxShadow(
            color: _kAccentDeepColor.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.84),
            accent.withValues(alpha: 0.16),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -10,
            child: Container(
              width: large ? 94 : 68,
              height: large ? 94 : 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: large ? 56 : 46,
                height: large ? 56 : 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: _kAccentDeepColor,
                  size: large ? 28 : 24,
                ),
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: _kPanelTextColor,
                  fontSize: large ? 26 : 18,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _kPanelMutedTextColor,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _kAccentDeepColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _kPanelTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _StoryCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kAccentSoftColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _kAccentDeepColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _kPanelTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: _kPanelMutedTextColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainPullCue extends StatelessWidget {
  final double progress;
  final double phase;
  final bool visible;

  const _MainPullCue({
    required this.progress,
    required this.phase,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = visible ? (1.0 - progress * 1.8).clamp(0.0, 1.0) : 0.0;
    final bob = math.sin(phase * 2 * math.pi) * 6.0;
    final ringSweep = (0.18 + progress * 0.72).clamp(0.18, 0.9);
    final chevronSpread = 10 + progress * 18;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 160),
        child: Transform.translate(
          offset: Offset(0, bob),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: CustomPaint(
                  painter: _PullCuePainter(
                    ringSweep: ringSweep,
                    chevronSpread: chevronSpread,
                    color: _kAccentColor,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 68 - progress * 16,
                height: 8 + progress * 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: _kAccentDeepColor.withValues(alpha: 0.10),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHandle extends StatelessWidget {
  final double progress;
  final double refreshProgress;
  final bool readyToRefresh;
  final bool readyToOpen;
  final bool refreshing;
  final double closeProgress;
  final bool showCloseCue;

  const _PanelHandle({
    required this.progress,
    required this.refreshProgress,
    required this.readyToRefresh,
    required this.readyToOpen,
    required this.refreshing,
    required this.closeProgress,
    required this.showCloseCue,
  });

  @override
  Widget build(BuildContext context) {
    final handleWidth = 40 + progress * 18 - closeProgress * 8;
    final handleHeight = 4 + progress * 2;
    final strokeColor = _kAccentDeepColor;
    final bgColor = _kAccentColor.withValues(alpha: 0.12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: handleWidth.clamp(30.0, 58.0),
          height: handleHeight.clamp(4.0, 6.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.88),
                _kAccentSoftColor.withValues(alpha: 0.68),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: _kAccentDeepColor.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 42,
          height: 42,
          child: refreshing
              ? const _RefreshOrbitIndicator()
              : CustomPaint(
                  painter: _HandleStatePainter(
                    progress: refreshProgress,
                    closeProgress: closeProgress,
                    strokeColor: strokeColor,
                    bgColor: bgColor,
                    readyToRefresh: readyToRefresh,
                    readyToOpen: readyToOpen,
                    showCloseCue: showCloseCue,
                  ),
                ),
        ),
      ],
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

class _PanelSurfacePainter extends CustomPainter {
  final double progress;

  _PanelSurfacePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final topGlowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.72),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.28, 1.0],
      ).createShader(Offset.zero & size);

    final glowHeight = math.min(size.height, 180.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, glowHeight), topGlowPaint);

    final waveDepth = (24.0 - progress * 12.0).clamp(10.0, 24.0);
    final path = Path()..moveTo(0, 0);
    path.quadraticBezierTo(
      size.width * 0.22,
      waveDepth,
      size.width * 0.5,
      waveDepth * 0.78,
    );
    path.quadraticBezierTo(size.width * 0.78, waveDepth * 0.52, size.width, 0);

    final edgePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.95),
          _kAccentSoftColor.withValues(alpha: 0.38),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, waveDepth));
    canvas.drawPath(
      path,
      edgePaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final highlightPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, glowHeight * 0.14),
              radius: size.width * 0.48,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.5, glowHeight * 0.14),
      size.width * 0.48,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PanelSurfacePainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

class _PullCuePainter extends CustomPainter {
  final double ringSweep;
  final double chevronSpread;
  final Color color;

  _PullCuePainter({
    required this.ringSweep,
    required this.chevronSpread,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * 0.28;

    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final activePaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius, ringPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * ringSweep,
      false,
      activePaint,
    );

    final chevronPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4;

    final topY = center.dy - chevronSpread * 0.7;
    final midY = center.dy + chevronSpread * 0.15;
    final bottomY = center.dy + chevronSpread;

    final path = Path()
      ..moveTo(center.dx - 14, topY)
      ..lineTo(center.dx, midY)
      ..lineTo(center.dx + 14, topY)
      ..moveTo(center.dx - 10, midY)
      ..lineTo(center.dx, bottomY)
      ..lineTo(center.dx + 10, midY);

    canvas.drawPath(path, chevronPaint);
  }

  @override
  bool shouldRepaint(covariant _PullCuePainter oldDelegate) {
    return ringSweep != oldDelegate.ringSweep ||
        chevronSpread != oldDelegate.chevronSpread ||
        color != oldDelegate.color;
  }
}

class _HandleStatePainter extends CustomPainter {
  final double progress;
  final double closeProgress;
  final Color strokeColor;
  final Color bgColor;
  final bool readyToRefresh;
  final bool readyToOpen;
  final bool showCloseCue;

  _HandleStatePainter({
    required this.progress,
    required this.closeProgress,
    required this.strokeColor,
    required this.bgColor,
    required this.readyToRefresh,
    required this.readyToOpen,
    required this.showCloseCue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    final basePaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, basePaint);

    final activePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = readyToOpen ? 4 : 3;

    final sweep = readyToOpen ? 2 * math.pi : math.pi * 2 * progress;
    if (sweep > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        activePaint,
      );
    }

    if (readyToOpen) {
      final dotPaint = Paint()..color = strokeColor;
      canvas.drawCircle(center, 4.5, dotPaint);
      return;
    }

    final cuePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.8;

    final direction = showCloseCue ? -1.0 : 1.0;
    final spread = 7 + closeProgress * 4;
    final path = Path()
      ..moveTo(center.dx - 7, center.dy - spread * direction * 0.2)
      ..lineTo(center.dx, center.dy + spread * direction * 0.45)
      ..lineTo(center.dx + 7, center.dy - spread * direction * 0.2);
    canvas.drawPath(path, cuePaint);

    if (readyToRefresh) {
      final glowPaint = Paint()
        ..color = strokeColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius - 3, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandleStatePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        closeProgress != oldDelegate.closeProgress ||
        strokeColor != oldDelegate.strokeColor ||
        bgColor != oldDelegate.bgColor ||
        readyToRefresh != oldDelegate.readyToRefresh ||
        readyToOpen != oldDelegate.readyToOpen ||
        showCloseCue != oldDelegate.showCloseCue;
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
          color: Colors.white.withValues(alpha: 0.18),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 56),
          child: const _RefreshOrbitIndicator(),
        ),
      ),
    );
  }
}

class _RefreshOrbitIndicator extends StatefulWidget {
  const _RefreshOrbitIndicator();

  @override
  State<_RefreshOrbitIndicator> createState() => _RefreshOrbitIndicatorState();
}

class _RefreshOrbitIndicatorState extends State<_RefreshOrbitIndicator>
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
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return CustomPaint(painter: _RefreshOrbitPainter(turns: _c.value));
        },
      ),
    );
  }
}

class _RefreshOrbitPainter extends CustomPainter {
  final double turns;

  _RefreshOrbitPainter({required this.turns});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;

    final ringPaint = Paint()
      ..color = _kAccentColor.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, ringPaint);

    final arcPaint = Paint()
      ..color = _kAccentDeepColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      turns * 2 * math.pi - math.pi / 2,
      math.pi * 1.35,
      false,
      arcPaint,
    );

    for (final phase in [0.0, 0.33, 0.66]) {
      final t = (turns + phase) % 1.0;
      final angle = t * 2 * math.pi - math.pi / 2;
      final orbitRadius = radius - 3 + 2 * math.sin(t * 2 * math.pi);
      final dotCenter = Offset(
        center.dx + math.cos(angle) * orbitRadius,
        center.dy + math.sin(angle) * orbitRadius,
      );
      final dotPaint = Paint()
        ..color = _kAccentSoftColor.withValues(
          alpha: 0.45 + 0.35 * (1 - phase),
        );
      canvas.drawCircle(dotCenter, 2.5 + (1 - phase), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RefreshOrbitPainter oldDelegate) {
    return turns != oldDelegate.turns;
  }
}

void registerPullPanelDemo() {
  demoRegistry.register(PullPanelDemo());
}
