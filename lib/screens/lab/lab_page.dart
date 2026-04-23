import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../lab/lab_container.dart';
import '../../lab/providers/lab_card_provider.dart';
import '../../services/lab_image_cache_service.dart';
import '../../widgets/image_picker_widget.dart';

enum LabPullPanelState {
  collapsed,
  draggingMain,
  draggingPanel,
  settling,
  expanded,
}

enum LabPullPanelActionType { none, animateTo }

class LabPullPanelAction {
  final LabPullPanelActionType type;
  final double? targetProgress;

  const LabPullPanelAction._(this.type, {this.targetProgress});

  const LabPullPanelAction.none() : this._(LabPullPanelActionType.none);

  const LabPullPanelAction.animateTo(double target)
    : this._(LabPullPanelActionType.animateTo, targetProgress: target);
}

class LabPullPanelMetrics {
  static const double topEpsilon = 0.5;
  static const double mainDragDeadZone = 8.0;
  static const double panelDragDeadZone = 8.0;
  static const double collapsedEpsilon = 0.001;
  static const double openThreshold = 0.22;
  static const double closeThresholdPx = 96.0;
  static const double velocityOpen = 500;
  static const double velocityClose = -500;
  static const double dragDamping = 0.8;
  static const double overdragResistance = 0.10;
  static const double mainPushRatio = 0.60;

  const LabPullPanelMetrics._();

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

class LabPullPanelStateMachine {
  LabPullPanelState _state = LabPullPanelState.collapsed;
  double _progress = 0.0;
  double _pendingMainDragDy = 0.0;
  double _pendingPanelDragDy = 0.0;
  double _panelDragDistancePx = 0.0;

  LabPullPanelState get state => _state;
  double get progress => _progress;

  bool get mainContentInteractive => _state == LabPullPanelState.collapsed;

  bool get panelScrollable =>
      _state == LabPullPanelState.expanded ||
      _state == LabPullPanelState.draggingPanel;

  bool get showMainCue =>
      _state == LabPullPanelState.collapsed ||
      _state == LabPullPanelState.draggingMain;

  bool get showCloseCue =>
      _state == LabPullPanelState.expanded ||
      _state == LabPullPanelState.draggingPanel;

  bool get readyToOpen => _progress >= LabPullPanelMetrics.openThreshold;

  double get closeProgress {
    if (_progress >= 1.0) return 0.0;
    return ((1.0 - _progress) / LabPullPanelMetrics.openThreshold)
        .clamp(0.0, 1.0);
  }

  void syncProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
    if (_progress <= 0.0 && _state != LabPullPanelState.settling) {
      _state = LabPullPanelState.collapsed;
    }
  }

  void beginMainDrag() {
    if (_state == LabPullPanelState.settling ||
        _state == LabPullPanelState.expanded ||
        _state == LabPullPanelState.draggingPanel) {
      return;
    }
    _pendingMainDragDy = 0.0;
  }

  void updateMainDrag({required double deltaDy, required double fullHeight}) {
    var effectiveDeltaDy = deltaDy;

    if (_state != LabPullPanelState.draggingMain) {
      _pendingMainDragDy += effectiveDeltaDy;
      final passedDeadZone =
          _pendingMainDragDy.abs() >= LabPullPanelMetrics.mainDragDeadZone;
      if (!passedDeadZone) return;

      if (_pendingMainDragDy <= 0) {
        _pendingMainDragDy = 0.0;
        return;
      }

      _state = LabPullPanelState.draggingMain;
      effectiveDeltaDy = _pendingMainDragDy;
      _pendingMainDragDy = 0.0;
    }

    _progress = LabPullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: effectiveDeltaDy,
      fullHeight: fullHeight,
    );
  }

  LabPullPanelAction endMainDrag({required double velocityDy}) {
    if (_state != LabPullPanelState.draggingMain) {
      _pendingMainDragDy = 0.0;
      if (_progress <= LabPullPanelMetrics.collapsedEpsilon) {
        _progress = 0.0;
        _state = LabPullPanelState.collapsed;
      }
      return const LabPullPanelAction.none();
    }

    _pendingMainDragDy = 0.0;

    if (_progress <= LabPullPanelMetrics.collapsedEpsilon) {
      _progress = 0.0;
      _state = LabPullPanelState.collapsed;
      return const LabPullPanelAction.none();
    }

    final shouldOpen =
        _progress >= LabPullPanelMetrics.openThreshold ||
        velocityDy > LabPullPanelMetrics.velocityOpen;

    _state = LabPullPanelState.settling;
    return LabPullPanelAction.animateTo(shouldOpen ? 1.0 : 0.0);
  }

  void beginPanelDrag() {
    if (_state == LabPullPanelState.draggingPanel) return;
    if (_state == LabPullPanelState.settling ||
        _state == LabPullPanelState.collapsed ||
        _state == LabPullPanelState.draggingMain) {
      return;
    }
    _pendingPanelDragDy = 0.0;
    _panelDragDistancePx = 0.0;
  }

  void updatePanelDrag({
    required double deltaDy,
    required double fullHeight,
  }) {
    if (_state != LabPullPanelState.expanded &&
        _state != LabPullPanelState.draggingPanel) {
      return;
    }

    var effectiveDeltaDy = deltaDy;

    if (_state != LabPullPanelState.draggingPanel) {
      _pendingPanelDragDy += effectiveDeltaDy;
      final passedDeadZone =
          _pendingPanelDragDy.abs() >= LabPullPanelMetrics.panelDragDeadZone;
      if (!passedDeadZone) return;

      if (_pendingPanelDragDy >= 0) {
        _pendingPanelDragDy = 0.0;
        return;
      }

      _state = LabPullPanelState.draggingPanel;
      effectiveDeltaDy = _pendingPanelDragDy;
      _pendingPanelDragDy = 0.0;
    }

    _state = LabPullPanelState.draggingPanel;
    if (effectiveDeltaDy < 0) {
      _panelDragDistancePx += -effectiveDeltaDy;
    }
    _progress = LabPullPanelMetrics.applyDrag(
      currentProgress: _progress,
      deltaDy: effectiveDeltaDy,
      fullHeight: fullHeight,
    );
  }

  LabPullPanelAction endPanelDrag({required double velocityDy}) {
    if (_state != LabPullPanelState.draggingPanel) {
      _pendingPanelDragDy = 0.0;
      _panelDragDistancePx = 0.0;
      return const LabPullPanelAction.none();
    }

    _pendingPanelDragDy = 0.0;
    _state = LabPullPanelState.settling;
    final shouldClose =
        _panelDragDistancePx >= LabPullPanelMetrics.closeThresholdPx ||
        velocityDy < LabPullPanelMetrics.velocityClose;
    _panelDragDistancePx = 0.0;
    return LabPullPanelAction.animateTo(shouldClose ? 0.0 : 1.0);
  }

  void onAnimationStarted() {
    _pendingMainDragDy = 0.0;
    _pendingPanelDragDy = 0.0;
    _panelDragDistancePx = 0.0;
    _state = LabPullPanelState.settling;
  }

  void onAnimationCompleted(double targetProgress) {
    _pendingMainDragDy = 0.0;
    _pendingPanelDragDy = 0.0;
    _panelDragDistancePx = 0.0;
    _progress = targetProgress.clamp(0.0, 1.0);
    if (_progress <= 0.0) {
      _state = LabPullPanelState.collapsed;
    } else if (_progress >= 1.0) {
      _state = LabPullPanelState.expanded;
    } else {
      _state = LabPullPanelState.collapsed;
    }
  }
}

const _kPanelGradientTop = Color(0xFFF8F3EE);
const _kPanelGradientMiddle = Color(0xFFEFE6DD);
const _kPanelGradientBottom = Color(0xFFE4D6C8);
const _kPanelBorderColor = Color(0x59FFFFFF);
const _kAccentColor = Color(0xFFC88A5A);
const _kAccentSoftColor = Color(0xFFD9A97C);
const _kAccentDeepColor = Color(0xFF8B5E3C);
const _kPanelTextColor = Color(0xFF5E4735);
const _kPanelMutedTextColor = Color(0xFF8E7561);
const _kCardBaseColor = Color(0xF2FFFCF8);
const _kAnimationDuration = Duration(milliseconds: 260);
const _kWaveDuration = Duration(seconds: 2);

class LabPage extends StatefulWidget {
  const LabPage({super.key});

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> with TickerProviderStateMixin {
  final LabPullPanelStateMachine _sm = LabPullPanelStateMachine();
  final ScrollController _gridScrollController = ScrollController();
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
  double _estimatedVelocityDy = 0.0;
  double _lastPointerY = 0.0;
  DateTime? _lastPointerTime;
  double _lastViewportHeight = 0.0;

  double get _progress => _sm.progress;

  @override
  void dispose() {
    _progressAnim?.removeListener(_onAnimTick);
    _anim.dispose();
    _waveController.dispose();
    _gridScrollController.dispose();
    _panelScrollController.dispose();
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

    _progressAnim = Tween<double>(
      begin: _progress,
      end: target,
    ).animate(
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

  void _runAction(LabPullPanelAction action) {
    switch (action.type) {
      case LabPullPanelActionType.none:
        setState(() {});
      case LabPullPanelActionType.animateTo:
        _animateTo(action.targetProgress!);
    }
  }

  void _trackVelocity(double currentY) {
    final now = DateTime.now();
    final lastTime = _lastPointerTime;
    if (lastTime != null) {
      final dtMs = now.difference(lastTime).inMilliseconds;
      if (dtMs > 0) {
        final dy = currentY - _lastPointerY;
        _estimatedVelocityDy = dy / dtMs * 1000;
      }
    }
    _lastPointerY = currentY;
    _lastPointerTime = now;
  }

  void _onPointerDown(PointerDownEvent event) {
    _lastPointerY = event.position.dy;
    _lastPointerTime = DateTime.now();
    _estimatedVelocityDy = 0.0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _trackVelocity(event.position.dy);

    if (_sm.state == LabPullPanelState.draggingMain &&
        _lastViewportHeight > 0) {
      _sm.updateMainDrag(
        deltaDy: event.delta.dy,
        fullHeight: _lastViewportHeight,
      );
      setState(() {});
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_sm.state == LabPullPanelState.draggingMain) {
      _runAction(_sm.endMainDrag(velocityDy: _estimatedVelocityDy));
    }
  }

  bool _onMainContentNotification(
    ScrollNotification notification,
    double fullHeight,
  ) {
    if (!_gridScrollController.hasClients) return false;
    if (!_sm.mainContentInteractive) return false;

    final atTop =
        _gridScrollController.position.extentBefore <=
        LabPullPanelMetrics.topEpsilon;

    if (!atTop) return false;

    if (notification is ScrollStartNotification) {
      _stopCurrentAnimation();
      _sm.beginMainDrag();
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final dy = notification.dragDetails!.delta.dy;
      if (dy > 0) {
        _sm.updateMainDrag(deltaDy: dy, fullHeight: fullHeight);
        setState(() {});
        return true;
      }
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      final dy = notification.dragDetails!.delta.dy;
      if (dy > 0) {
        _stopCurrentAnimation();
        _sm.beginMainDrag();
        _sm.updateMainDrag(deltaDy: dy, fullHeight: fullHeight);
        setState(() {});
        return true;
      }
    }

    if (notification is ScrollEndNotification &&
        _sm.state == LabPullPanelState.draggingMain) {
      _runAction(_sm.endMainDrag(velocityDy: _estimatedVelocityDy));
      return true;
    }

    return false;
  }

  void _onPanelHandleDragStart() {
    _stopCurrentAnimation();
    _sm.beginPanelDrag();
    setState(() {});
  }

  void _onPanelHandleDragUpdate(double deltaDy, double fullHeight) {
    if (deltaDy >= 0) return;
    _sm.updatePanelDrag(deltaDy: deltaDy, fullHeight: fullHeight);
    setState(() {});
  }

  void _onPanelHandleDragEnd(double velocityDy) {
    _runAction(_sm.endPanelDrag(velocityDy: velocityDy));
  }

  @override
  Widget build(BuildContext context) {
    final demos = demoRegistry.getAll();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Lab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => _showCacheInfo(context),
            tooltip: 'Cache',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showLabInfo(context),
          ),
        ],
      ),
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fullHeight = constraints.maxHeight;
            _lastViewportHeight = fullHeight;
            final mainPush =
                fullHeight * LabPullPanelMetrics.mainPushRatio * _progress;
            final panelHeight = fullHeight * _progress;
            final mainScale = 1.0 - (_progress * 0.02);

            return Stack(
              children: [
                Transform.translate(
                  offset: Offset(0, mainPush),
                  child: Transform.scale(
                    scale: mainScale,
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(
                      ignoring: !_sm.mainContentInteractive,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          return _onMainContentNotification(
                            notification,
                            fullHeight,
                          );
                        },
                        child: Stack(
                          children: [
                            if (demos.isEmpty)
                              _buildEmptyState(Theme.of(context))
                            else
                              _buildDemoGrid(demos),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: panelHeight,
                  child: ClipRect(
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
                        _LabPanelContent(
                          scrollController: _panelScrollController,
                          demos: demos,
                          scrollable: _sm.panelScrollable,
                          progress: _progress,
                          readyToOpen: _sm.readyToOpen,
                          closeProgress: _sm.closeProgress,
                          showCloseCue: _sm.showCloseCue,
                          onHandleDragStart: _onPanelHandleDragStart,
                          onHandleDragUpdate: (deltaDy) {
                            _onPanelHandleDragUpdate(deltaDy, fullHeight);
                          },
                          onHandleDragEnd: _onPanelHandleDragEnd,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.science_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No demos available',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Register demos in main.dart first.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoGrid(List<MapEntry<String, DemoPage>> demos) {
    return _ScrollRevealGrid(
      demos: demos,
      controller: _gridScrollController,
      physics: _sm.mainContentInteractive
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
    );
  }

  void _showLabInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [Icon(Icons.science), SizedBox(width: 8), Text('Lab Info')],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This page hosts demos and experimental features.'),
            SizedBox(height: 12),
            Text('- Each demo runs independently'),
            Text('- Managed by the lab registry'),
            Text('- Safe to iterate without touching the main flow'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showCacheInfo(BuildContext context) async {
    final cacheService = LabImageCacheService();
    await cacheService.init();
    final cacheSize = await cacheService.getCacheSize();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services),
            SizedBox(width: 8),
            Text('Image Cache'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cache size: ${_formatBytes(cacheSize)}'),
            const SizedBox(height: 8),
            const Text('Thumbnails improve large-image loading performance.'),
            const SizedBox(height: 12),
            const Text('Clearing cache will regenerate preview images.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await cacheService.clearCache();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared')),
                );
              }
            },
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _LabPanelContent extends StatelessWidget {
  final ScrollController scrollController;
  final List<MapEntry<String, DemoPage>> demos;
  final bool scrollable;
  final double progress;
  final bool readyToOpen;
  final double closeProgress;
  final bool showCloseCue;
  final VoidCallback onHandleDragStart;
  final ValueChanged<double> onHandleDragUpdate;
  final ValueChanged<double> onHandleDragEnd;

  const _LabPanelContent({
    required this.scrollController,
    required this.demos,
    required this.scrollable,
    required this.progress,
    required this.readyToOpen,
    required this.closeProgress,
    required this.showCloseCue,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final contentOffset = (1.0 - progress) * 16.0;
    final contentScale = 0.5 + (progress * 0.5);
    final contentOpacity = progress.clamp(0.0, 1.0);
    final topTitles = demos.take(5).map((entry) => entry.value.title).toList();

    return Column(
      children: [
        Expanded(
          child: IgnorePointer(
            ignoring: !scrollable,
            child: Transform.translate(
              offset: Offset(0, contentOffset),
              child: Opacity(
                opacity: contentOpacity,
                child: Transform.scale(
                  scale: contentScale.clamp(0.5, 1.0),
                  alignment: Alignment.topCenter,
                  child: ListView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
                    children: [
                      _LabPanelHeroCard(
                        demoCount: demos.length,
                        topLabel: topTitles.isNotEmpty
                            ? topTitles.first
                            : 'No demos',
                      ),
                      const SizedBox(height: 18),
                      const _PanelSectionHeader(
                        eyebrow: 'REGISTRY',
                        title: 'Quick read of the lab space',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _ActionChip(
                            icon: Icons.widgets_outlined,
                            label: '${demos.length} demos',
                          ),
                          const _ActionChip(
                            icon: Icons.vertical_align_top,
                            label: 'Top overscroll opens',
                          ),
                          const _ActionChip(
                            icon: Icons.pan_tool_alt_outlined,
                            label: 'Handle drag closes',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _PanelSectionHeader(
                        eyebrow: 'RECENT',
                        title: 'Registered demo entries',
                      ),
                      const SizedBox(height: 12),
                      for (final demo in topTitles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StoryCard(
                            icon: Icons.chevron_right,
                            title: demo,
                            body:
                                'Registry entry available from the Lab grid and this pull panel.',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => onHandleDragStart(),
            onVerticalDragUpdate: (details) {
              onHandleDragUpdate(details.delta.dy);
            },
            onVerticalDragEnd: (details) {
              onHandleDragEnd(details.velocity.pixelsPerSecond.dy);
            },
            onVerticalDragCancel: () => onHandleDragEnd(0.0),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Center(
                  child: _PanelHandle(
                    progress: progress,
                    readyToOpen: readyToOpen,
                    closeProgress: closeProgress,
                    showCloseCue: showCloseCue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabPanelHeroCard extends StatelessWidget {
  final int demoCount;
  final String topLabel;

  const _LabPanelHeroCard({
    required this.demoCount,
    required this.topLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lab Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: _kPanelTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The panel opens with the same threshold, damping and close handle feel as the pull panel demo.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _kPanelMutedTextColor,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _MetricPill(label: 'Demos', value: '$demoCount'),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(label: 'First', value: topLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCardBaseColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _kPanelMutedTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _kPanelTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;

  const _PanelSectionHeader({required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _kPanelMutedTextColor,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _kPanelTextColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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

class _DemoCard extends StatefulWidget {
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DemoCard({
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  State<_DemoCard> createState() => _DemoCardState();
}

class _DemoCardState extends State<_DemoCard> {
  final _provider = LabCardProvider();
  final _cacheService = LabImageCacheService();
  bool _isPressed = false;
  Uint8List? _cachedImageBytes;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
    _cacheService.init();
    _initAndPreload();
  }

  Future<void> _initAndPreload() async {
    await _provider.onLoaded;
    if (mounted) _preloadImage();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() async {
    if (mounted) {
      await _provider.onLoaded;
      if (mounted) {
        _preloadImage();
        setState(() {});
      }
    }
  }

  Future<void> _preloadImage() async {
    final backgroundUrl = _provider.getBackground(widget.title);
    if (backgroundUrl != null && _provider.isLocalFile(widget.title)) {
      final bytes = await _cacheService.getThumbnailBytes(backgroundUrl);
      if (bytes != null && mounted) {
        setState(() {
          _cachedImageBytes = bytes;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundUrl = _provider.getBackground(widget.title);
    final isLocalFile =
        backgroundUrl != null && _provider.isLocalFile(widget.title);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: () => _showBackgroundDialog(context),
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backgroundUrl != null && backgroundUrl.isNotEmpty)
                Positioned.fill(
                  child: isLocalFile
                      ? _buildLocalImage(backgroundUrl, theme)
                      : _buildNetworkImage(backgroundUrl, theme),
                ),
              if (backgroundUrl != null && backgroundUrl.isNotEmpty)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.widgets,
                      color: backgroundUrl != null
                          ? Colors.white
                          : theme.colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: backgroundUrl != null ? Colors.white : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        widget.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: backgroundUrl != null
                              ? Colors.white70
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Widget _buildNetworkImage(String url, ThemeData theme) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(color: theme.colorScheme.surfaceContainerHighest);
      },
    );
  }

  Widget _buildLocalImage(String path, ThemeData theme) {
    if (_cachedImageBytes != null) {
      return Image.memory(
        _cachedImageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image),
        ),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image),
      ),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }

  void _showBackgroundDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BackgroundSettingSheet(
        currentUrl: _provider.getBackground(widget.title),
        isLocalFile: _provider.isLocalFile(widget.title),
        onImageSelected: (url) async {
          await _provider.setBackground(widget.title, url);
          if (context.mounted) Navigator.pop(context);
        },
        onRemove: () async {
          await _provider.removeBackground(widget.title);
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

class _BackgroundSettingSheet extends StatefulWidget {
  final String? currentUrl;
  final bool isLocalFile;
  final Future<void> Function(String) onImageSelected;
  final VoidCallback onRemove;

  const _BackgroundSettingSheet({
    required this.currentUrl,
    this.isLocalFile = false,
    required this.onImageSelected,
    required this.onRemove,
  });

  @override
  State<_BackgroundSettingSheet> createState() =>
      _BackgroundSettingSheetState();
}

class _BackgroundSettingSheetState extends State<_BackgroundSettingSheet> {
  String _customUrl = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image, size: 24),
              const SizedBox(width: 8),
              Text('Set Background Image', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (widget.currentUrl != null)
                TextButton.icon(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _pickAndCropImage,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.crop),
                  label: const Text('Pick And Crop'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickLocalImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Pick Only'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Custom Image URL', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/image.jpg',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) => _customUrl = value,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _isLoading || _customUrl.isEmpty
                    ? null
                    : () => _selectImage(_customUrl),
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Preset Images', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
              ),
              itemCount: LabCardProvider.presetImages.length,
              itemBuilder: (context, index) {
                final url = LabCardProvider.presetImages[index];
                final isSelected = widget.currentUrl == url;

                return GestureDetector(
                  onTap: () => _selectImage(url),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image),
                              ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 32,
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

  Future<void> _pickAndCropImage() async {
    setState(() => _isLoading = true);
    try {
      final imagePath = await ImagePickerPage.navigate(
        context,
        config: const ImagePickerConfig(
          aspectRatioX: 1,
          aspectRatioY: 1,
          lockAspectRatio: false,
        ),
        initialImagePath: widget.isLocalFile ? widget.currentUrl : null,
        title: 'Set Card Background',
        emptyStateHint: 'Select a background image',
        emptyStateSubHint: 'Freely adjust the crop area',
      );
      if (imagePath != null) {
        await widget.onImageSelected(imagePath);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLocalImage() async {
    setState(() => _isLoading = true);
    try {
      final imagePath = await ImagePickerPage.navigate(
        context,
        config: const ImagePickerConfig(enableCrop: false),
        initialImagePath: widget.isLocalFile ? widget.currentUrl : null,
        title: 'Select Background Image',
        emptyStateHint: 'Select a background image',
        emptyStateSubHint: '',
      );
      if (imagePath != null) {
        await widget.onImageSelected(imagePath);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectImage(String url) async {
    setState(() => _isLoading = true);
    try {
      await widget.onImageSelected(url);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _DemoDetailPage extends StatelessWidget {
  final DemoPage demo;

  const _DemoDetailPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: demo.preferFullScreen
          ? null
          : AppBar(
              title: GestureDetector(
                onTap: () => _showDemoDesc(context),
                behavior: HitTestBehavior.opaque,
                child: Text(demo.title),
              ),
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
      body: demo.buildPage(context),
    );
  }

  void _showDemoDesc(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.widgets),
            const SizedBox(width: 8),
            Flexible(child: Text(demo.title)),
          ],
        ),
        content: Text(demo.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ScrollRevealGrid extends StatefulWidget {
  const _ScrollRevealGrid({
    required this.demos,
    required this.controller,
    required this.physics,
  });

  final List<MapEntry<String, DemoPage>> demos;
  final ScrollController controller;
  final ScrollPhysics physics;

  @override
  State<_ScrollRevealGrid> createState() => _ScrollRevealGridState();
}

class _ScrollRevealGridState extends State<_ScrollRevealGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: widget.controller,
      physics: widget.physics,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: widget.demos.length,
      itemBuilder: (context, index) {
        final demo = widget.demos[index].value;
        return _RevealItem(
          index: index,
          controller: _controller,
          child: _DemoCard(
            title: demo.title,
            description: demo.description,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => _DemoDetailPage(demo: demo),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RevealItem extends StatefulWidget {
  const _RevealItem({
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final AnimationController controller;
  final Widget child;

  @override
  State<_RevealItem> createState() => _RevealItemState();
}

class _RevealItemState extends State<_RevealItem> {
  double get _delay => (widget.index * 0.06).clamp(0.0, 0.72);
  double get _dur => 0.28;

  double _progress(double t) {
    final start = _delay;
    final end = start + _dur;
    if (t < start) return 0.0;
    if (t >= end) return 1.0;
    return Curves.easeOutCubic.transform((t - start) / (end - start));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final p = _progress(widget.controller.value);
        if (p >= 1.0) {
          return widget.child;
        }
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - p)),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _PanelHandle extends StatelessWidget {
  final double progress;
  final bool readyToOpen;
  final double closeProgress;
  final bool showCloseCue;

  const _PanelHandle({
    required this.progress,
    required this.readyToOpen,
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
          child: CustomPaint(
            painter: _HandleStatePainter(
              progress: readyToOpen ? 1.0 : progress.clamp(0.0, 1.0),
              closeProgress: closeProgress,
              strokeColor: strokeColor,
              bgColor: bgColor,
              readyToOpen: readyToOpen,
              showCloseCue: showCloseCue,
            ),
          ),
        ),
      ],
    );
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

class _HandleStatePainter extends CustomPainter {
  final double progress;
  final double closeProgress;
  final Color strokeColor;
  final Color bgColor;
  final bool readyToOpen;
  final bool showCloseCue;

  _HandleStatePainter({
    required this.progress,
    required this.closeProgress,
    required this.strokeColor,
    required this.bgColor,
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
  }

  @override
  bool shouldRepaint(covariant _HandleStatePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        closeProgress != oldDelegate.closeProgress ||
        strokeColor != oldDelegate.strokeColor ||
        bgColor != oldDelegate.bgColor ||
        readyToOpen != oldDelegate.readyToOpen ||
        showCloseCue != oldDelegate.showCloseCue;
  }
}
