import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/entities/reorderable_animation_config.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../../../lab/lab_container.dart';
import 'demo_detail_page.dart';
import 'providers/lab_card_provider.dart';
import '../../../services/lab_image_cache_service.dart';
import '../../../widgets/image_picker_widget.dart';
import '../../../core/color/color_utils.dart';

part 'lab_page/const_lab_panel.dart';
part 'lab_page/components.dart';
part 'lab_page/panel_content.dart';
part 'lab_page/panel_state.dart';

const bool _kLabPanelPerfDebug = false;

void _labPerfLog(String message) {
  if (_kLabPanelPerfDebug && kDebugMode) {
    debugPrint('[LabPagePerf] $message');
  }
}

class LabPage extends StatefulWidget {
  /// 是否排除游戏类 demo。默认 true：实验室语义下游戏统一由游戏中心承载。
  final bool excludeGames;

  const LabPage({super.key, this.excludeGames = true});

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> with TickerProviderStateMixin {
  final LabPullPanelStateMachine _sm = LabPullPanelStateMachine();
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _panelScrollController = ScrollController();

  /// demos 在 main.dart bootstrapLab() 同步注册完成、早于本页构建，
  /// 缓存一次即可，避免面板拖拽每帧 setState 时 getAll().toList() 重新分配。
  late final List<MapEntry<String, DemoPage>> _demos;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: _kAnimationDuration,
  )..addStatusListener(_onAnimationStatusChanged);

  Animation<double>? _progressAnim;
  double? _pendingAnimationTarget;
  double _estimatedVelocityDy = 0.0;
  double _lastPointerY = 0.0;
  DateTime? _lastPointerTime;
  double _lastViewportHeight = 0.0;
  late final TimingsCallback _timingsCallback = _onFrameTimings;

  /// 面板展开进度的**连续**通道：拖拽/动画每帧只改它，不走 setState。
  /// 订阅方（AppBar 折叠、主内容位移、面板高度、面板内部变换、把手）各自
  /// ValueListenableBuilder，重建范围收敛到几个包装 widget；demo 网格与面板
  /// 列表实例在 build 里只造一次，靠 widget identity 短路，子树完全不重建。
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);

  /// 状态机的**离散**通道：只有 state 真的换了才 setState（影响可交互性、
  /// 可滚动性、返回键拦截这些非每帧变化的东西）。
  LabPullPanelState _publishedState = LabPullPanelState.collapsed;

  @override
  void initState() {
    super.initState();
    // demos 在 main.dart bootstrapLab() 同步注册完成、早于本页构建，
    // 缓存一次即可，避免面板拖拽每帧 setState 时 getAll().toList() 重新分配。
    //
    // 别名去重：demoRegistry.register(demo, key: alias) 会让同一 demo
    // 实例在 _bySlug 里出现多次（key 不同、value 同），getAll() 返回全部
    // 条目用于路由 / URL 生成 — UI 渲染需按 demo 实例 distinct，否则别名
    // 会在 lab 列表里重复显示多张相同卡片（如 rive-demo 的 main +
    // rive-pendulum + rive-data-bind + demo-lab 4 个 slug 指向同一实例）。
    // 按 entries 顺序保留首个 slug = 注册时最先写的主 slug。
    final seen = <DemoPage>{};
    _demos =
        (widget.excludeGames
                ? demoRegistry.getAll().where(
                    (e) => e.value.type != DemoType.game,
                  )
                : demoRegistry.getAll())
            .where((e) => seen.add(e.value))
            .toList();
    if (_kLabPanelPerfDebug && kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    }
  }

  double get _progress => _sm.progress;
  bool get _panelConsumesBack =>
      _progress > LabPullPanelMetrics.collapsedEpsilon ||
      _sm.state == LabPullPanelState.settling;

  /// 状态机变更后统一从这里出口：连续量走 notifier，离散量才 setState。
  /// 所有原先「改完 _sm 就 setState(() {})」的位置一律换成本方法。
  void _publish() {
    if (!mounted) return;
    _progressNotifier.value = _sm.progress;
    if (_publishedState != _sm.state) {
      _publishedState = _sm.state;
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (_kLabPanelPerfDebug && kDebugMode) {
      SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    }
    _progressAnim?.removeListener(_onAnimTick);
    _anim.dispose();
    _gridScrollController.dispose();
    _panelScrollController.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_kLabPanelPerfDebug || !mounted) return;

    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      if (buildMs <= 8.0 && rasterMs <= 8.0) continue;
      _labPerfLog(
        'slow frame build=${buildMs.toStringAsFixed(1)}ms '
        'raster=${rasterMs.toStringAsFixed(1)}ms '
        'progress=${_progress.toStringAsFixed(3)} '
        'state=${_sm.state.name} '
        'animating=${_anim.isAnimating}',
      );
    }
  }

  void _stopCurrentAnimation({bool settleToTarget = false}) {
    final target = _pendingAnimationTarget;
    if (_anim.isAnimating) {
      _anim.stop();
    }
    _progressAnim?.removeListener(_onAnimTick);
    _progressAnim = null;
    if (settleToTarget && target != null) {
      _sm.onAnimationCompleted(target);
    } else {
      _sm.syncProgress(_progress);
    }
    _pendingAnimationTarget = null;
  }

  void _animateTo(double target) {
    _stopCurrentAnimation();
    _pendingAnimationTarget = target;
    _sm.onAnimationStarted();
    _labPerfLog(
      'animateTo target=${target.toStringAsFixed(3)} from=${_progress.toStringAsFixed(3)}',
    );

    _progressAnim = Tween<double>(begin: _progress, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    )..addListener(_onAnimTick);

    _publish();
    _anim.forward(from: 0.0);
  }

  void _onAnimTick() {
    final animation = _progressAnim;
    if (animation == null) return;
    _sm.syncProgress(animation.value);
    _publish();
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      // 动画被中断（如新拖拽开始），保持当前状态由下一次手势接管
      _labPerfLog(
        'animation dismissed pendingTarget=$_pendingAnimationTarget '
        'state=${_sm.state.name}',
      );
      return;
    }
    if (status != AnimationStatus.completed) return;
    final target = _pendingAnimationTarget;
    if (target == null) return;

    _progressAnim?.removeListener(_onAnimTick);
    _progressAnim = null;
    _pendingAnimationTarget = null;
    _sm.onAnimationCompleted(target);
    _labPerfLog(
      'animation completed target=${target.toStringAsFixed(3)} state=${_sm.state.name}',
    );
    _publish();
  }

  void _runAction(LabPullPanelAction action) {
    switch (action.type) {
      case LabPullPanelActionType.none:
        _publish();
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
      _publish();
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
      _labPerfLog('main scroll start progress=${_progress.toStringAsFixed(3)}');
      _stopCurrentAnimation(settleToTarget: true);
      _sm.beginMainDrag();
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final dy = notification.dragDetails!.delta.dy;
      if (dy > 0) {
        _sm.updateMainDrag(deltaDy: dy, fullHeight: fullHeight);
        _labPerfLog(
          'main drag update dy=${dy.toStringAsFixed(1)} progress=${_progress.toStringAsFixed(3)}',
        );
        _publish();
        return true;
      }
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      final dy = notification.dragDetails!.delta.dy;
      if (dy > 0) {
        _stopCurrentAnimation(settleToTarget: true);
        _sm.beginMainDrag();
        _sm.updateMainDrag(deltaDy: dy, fullHeight: fullHeight);
        _labPerfLog(
          'main overscroll dy=${dy.toStringAsFixed(1)} progress=${_progress.toStringAsFixed(3)}',
        );
        _publish();
        return true;
      }
    }

    if (notification is ScrollEndNotification &&
        _sm.state == LabPullPanelState.draggingMain) {
      _labPerfLog(
        'main drag end velocity=${_estimatedVelocityDy.toStringAsFixed(1)} progress=${_progress.toStringAsFixed(3)}',
      );
      _runAction(_sm.endMainDrag(velocityDy: _estimatedVelocityDy));
      return true;
    }

    return false;
  }

  void _onPanelHandleDragStart() {
    _stopCurrentAnimation(settleToTarget: true);
    _sm.beginPanelDrag();
    _labPerfLog('panel drag start progress=${_progress.toStringAsFixed(3)}');
    _publish();
  }

  void _onPanelHandleDragUpdate(double deltaDy, double fullHeight) {
    _sm.updatePanelDrag(deltaDy: deltaDy, fullHeight: fullHeight);
    _labPerfLog(
      'panel drag update dy=${deltaDy.toStringAsFixed(1)} progress=${_progress.toStringAsFixed(3)}',
    );
    _publish();
  }

  void _onPanelHandleDragEnd(double velocityDy) {
    _labPerfLog(
      'panel drag end velocity=${velocityDy.toStringAsFixed(1)} progress=${_progress.toStringAsFixed(3)}',
    );
    _runAction(_sm.endPanelDrag(velocityDy: velocityDy));
  }

  void _openDemoPage(BuildContext context, DemoPage demo) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DemoDetailPage(demo: demo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final demos = _demos;
    final theme = Theme.of(context);
    final panelColors = LabPanelColors.resolve(
      theme.colorScheme,
      brightness: theme.brightness,
    );
    // 下面三块是「重活」：主内容网格、面板背景、面板内容。
    // 它们在一次 build 里各造一个实例，随后每帧的 ValueListenableBuilder 都把
    // **同一个实例**传下去 —— Element.update 遇到 identical(newWidget, oldWidget)
    // 直接短路，子树不进 build。这是"拖拽不再整页重建"的关键。
    final mainContent = RepaintBoundary(
      child: demos.isEmpty ? _buildEmptyState(theme) : _buildDemoGrid(demos),
    );

    final panelBackground = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            panelColors.gradientTop,
            panelColors.gradientMiddle,
            panelColors.gradientBottom,
          ],
        ),
      ),
    );

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
          preferredSize: const Size.fromHeight(48),
          child: RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: _progressNotifier,
              builder: (context, progress, child) {
                final reveal = (1.0 - progress).clamp(0.0, 1.0);
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: reveal,
                    child: IgnorePointer(
                      ignoring: reveal <= 0.0,
                      child: Opacity(opacity: reveal, child: child),
                    ),
                  ),
                );
              },
              child: AppBar(
                toolbarHeight: 48,
                title: const Text('Lab'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.cleaning_services_outlined),
                    onPressed: () => _showCacheInfo(context),
                    tooltip: '缓存',
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
        body: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fullHeight = constraints.maxHeight;
              _lastViewportHeight = fullHeight;

              // 主内容层与面板内容层各自只造一次；下面的 VLB 每帧只重建
              // Stack / Transform / Positioned 这几个轻量包装。
              final mainLayer = IgnorePointer(
                ignoring: !_sm.mainContentInteractive,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    return _onMainContentNotification(notification, fullHeight);
                  },
                  child: mainContent,
                ),
              );

              final panelContent = _LabPanelContent(
                scrollController: _panelScrollController,
                demos: demos,
                panelColors: panelColors,
                scrollable: _sm.panelScrollable,
                progress: _progressNotifier,
                showCloseCue: _sm.showCloseCue,
                onHandleDragStart: _onPanelHandleDragStart,
                onHandleDragUpdate: (deltaDy) {
                  _onPanelHandleDragUpdate(deltaDy, fullHeight);
                },
                onHandleDragEnd: _onPanelHandleDragEnd,
                onDemoTap: (demo) => _openDemoPage(context, demo),
              );

              return ValueListenableBuilder<double>(
                valueListenable: _progressNotifier,
                builder: (context, progress, _) {
                  final mainPush =
                      fullHeight * LabPullPanelMetrics.mainPushRatio * progress;
                  return Stack(
                    children: [
                      Transform.translate(
                        offset: Offset(0, mainPush),
                        child: mainLayer,
                      ),
                      // 面板高度必须真的随 progress 收缩（把手要跟着上边缘走），
                      // 所以这里保持 Positioned + height，不能改成 Align 裁剪。
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: fullHeight * progress,
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Positioned.fill(child: panelBackground),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _PanelSurfacePainter(
                                    progress: progress,
                                    colors: panelColors,
                                  ),
                                ),
                              ),
                              panelContent,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
            '还没有可用的 demo',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先在 main.dart 的 bootstrapLab() 里注册',
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
          children: [Icon(Icons.science), SizedBox(width: 8), Text('关于 Lab')],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这里存放各类 demo 与实验性功能。'),
            SizedBox(height: 12),
            Text('· 每个 demo 独立运行'),
            Text('· 由 lab 注册表统一管理'),
            Text('· 可随意迭代，不影响主流程'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
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
            Text('图片缓存'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('缓存大小：${_formatBytes(cacheSize)}'),
            const SizedBox(height: 8),
            const Text('缩略图用于加速大图加载。'),
            const SizedBox(height: 12),
            const Text('清空后预览图会重新生成。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              await cacheService.clearCache();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('缓存已清空')));
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: const Text('清空缓存'),
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
