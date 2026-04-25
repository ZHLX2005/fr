import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../lab/lab_container.dart';
import '../../lab/providers/lab_card_provider.dart';
import '../../services/lab_image_cache_service.dart';
import '../../widgets/image_picker_widget.dart';

part 'lab_page/components.dart';
part 'lab_page/panel_content.dart';
part 'lab_page/panel_state.dart';

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
  bool get _panelConsumesBack =>
      _progress > LabPullPanelMetrics.collapsedEpsilon ||
      _sm.state == LabPullPanelState.settling;

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

  void _runAction(LabPullPanelAction action) {
    switch (action.type) {
      case LabPullPanelActionType.none:
        setState(() {});
      case LabPullPanelActionType.animateTo:
        _animateTo(action.targetProgress!);
    }
  }

  void _collapsePanel() {
    if (!_panelConsumesBack) return;
    _animateTo(0.0);
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
    _sm.updatePanelDrag(deltaDy: deltaDy, fullHeight: fullHeight);
    setState(() {});
  }

  void _onPanelHandleDragEnd(double velocityDy) {
    _runAction(_sm.endPanelDrag(velocityDy: velocityDy));
  }

  void _openDemoPage(BuildContext context, DemoPage demo) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => _DemoDetailPage(demo: demo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final demos = demoRegistry.getAll();
    final theme = Theme.of(context);
    final appBarReveal = (1.0 - _progress).clamp(0.0, 1.0);
    final appBarHeight =
        (kToolbarHeight + MediaQuery.of(context).padding.top) * appBarReveal;

    return PopScope(
      canPop: !_panelConsumesBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _collapsePanel();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(appBarHeight),
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: appBarReveal,
              child: Opacity(
                opacity: appBarReveal,
                child: IgnorePointer(
                  ignoring: appBarReveal <= 0.0,
                  child: AppBar(
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
                ),
              ),
            ),
          ),
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

              return Stack(
                children: [
                  Transform.translate(
                    offset: Offset(0, mainPush),
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
                            onDemoTap: (demo) => _openDemoPage(context, demo),
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
      onDemoTap: (demo) => _openDemoPage(context, demo),
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
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
