import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../../domain/chart_data.dart';
import '../../domain/constants.dart';
import '../../domain/game_result.dart';
import '../../game_controller.dart';
import '../../io/line_orientation.dart';
import '../../settings/line_settings.dart';
import '../painters/game_painter.dart';
import '../painters/water_effect_painter.dart';
import 'game_result_page.dart';
import 'song_select_page.dart';

class _LineDemoPage extends StatefulWidget {
  final ChartData chart;
  final String? audioPath;
  final String songId;

  const _LineDemoPage({
    required this.chart,
    this.audioPath,
    this.songId = '',
  });

  @override
  State<_LineDemoPage> createState() => _LineDemoPageState();
}

class _LineDemoPageState extends State<_LineDemoPage>
    with TickerProviderStateMixin {
  bool _isWaterEntering = true;
  bool _didInit = false;

  late AnimationController _exitController;
  late AnimationController _enterController;
  late AnimationController _healthController;
  late AnimationController _renderTicker;

  late GameController _controller;

  @override
  void initState() {
    super.initState();
    unawaited(LineOrientation.enableAll());

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _enterController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _healthController = AnimationController(
      duration: const Duration(days: 365),
      vsync: this,
    )..repeat();
    _renderTicker = AnimationController(
      duration: const Duration(milliseconds: 16),
      vsync: this,
    )..repeat();
    _renderTicker.addListener(_onTick);
  }

  void _onTick() {
    if (!_didInit) return;
    _controller.tick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) {
      final size = MediaQuery.of(context).size;
      _controller.updateScreenSize(size.width, size.height);
      return;
    }
    _didInit = true;

    final screenSize = MediaQuery.of(context).size;

    _controller = GameController(
      chart: widget.chart,
      audioPath: widget.audioPath,
      songId: widget.songId,
      vsync: this,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      themeColor: Theme.of(context).colorScheme.primary,
      onGameOver: _onGameOver,
    )..onStateChanged = () {
        if (mounted) setState(() {});
      };

    _enterController.value = 1.0;
    unawaited(() async {
      await _controller.init();
      if (!mounted) return;
      await _enterController.reverse();
      if (!mounted) return;
      setState(() => _isWaterEntering = false);
      _controller.startCountdown();
    }());
  }

  void _onGameOver(GameResult result) {
    if (!mounted) return;
    _exitController.reset();
    _exitController.forward().then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameResultPage(
            result: result,
            chart: widget.chart,
            audioPath: widget.audioPath,
            songId: widget.songId,
          ),
        ),
      );
    });
  }

  Future<void> _handleExit() async {
    if (_controller.isExiting) return;
    await _controller.handleExit();
    _exitController.reset();
    _exitController.forward().then((_) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SongSelectPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _renderTicker.removeListener(_onTick);
    _exitController.dispose();
    _enterController.dispose();
    _healthController.dispose();
    _renderTicker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final w = screenSize.width;
    final h = screenSize.height;
    final landscape = w > h;
    final c = _controller;

    // 横屏：游玩区居中，宽度不超过短边*1.15
    final layoutW = landscape ? (h * 1.15).clamp(0.0, w) : w;
    final playLeft = landscape ? (w - layoutW) / 2 : 0.0;
    final radius = (landscape ? h : w) / columnCount * noteSizeRatio;
    final judgeY = h * (landscape ? 0.82 : judgeLineRatio);

    if (_didInit) {
      c.updateScreenSize(layoutW, h);
    }

    final allControllers = <Listenable>[
      _healthController,
      _renderTicker,
      for (final col in c.notes)
        for (final note in col) note.controller,
      for (final e in c.explodes) e.controller,
      for (final fb in c.judgeFeedbacks) fb.controller,
    ];

    final padTop = MediaQuery.of(context).padding.top;
    final padLeft = MediaQuery.of(context).padding.left;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final local = e.localPosition;
            final dx = landscape ? local.dx - playLeft : local.dx;
            if (landscape && (dx < 0 || dx > layoutW)) return;
            c.handlePressAt(
              e.pointer,
              Offset(dx, local.dy),
              e.position,
            );
            setState(() {});
          },
          onPointerMove: (e) {
            c.handleMoveAt(e.pointer, e.position);
          },
          onPointerUp: (e) {
            c.handlePointerUp(e);
            setState(() {});
          },
          onPointerCancel: (e) {
            c.handlePointerCancel(e);
            setState(() {});
          },
          child: Stack(
            children: [
              Positioned(
                left: playLeft,
                top: 0,
                width: layoutW,
                height: h,
                child: AnimatedBuilder(
                  animation: Listenable.merge(allControllers),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: GamePainter(
                        columns: c.notes,
                        explodes: c.explodes,
                        color: theme.colorScheme.primary,
                        radius: radius,
                        screenWidth: layoutW,
                        screenHeight: h,
                        columnCount: columnCount,
                        judgeY: judgeY,
                        judgeFeedbacks: c.judgeFeedbacks,
                        backgroundStyle: c.backgroundStyle,
                        health: c.health,
                        dropDuration: widget.chart.dropDuration.toDouble(),
                        scrollSpeed: c.scrollSpeed,
                        gameElapsed: c.clockMs,
                        scheme: theme.colorScheme,
                        judgeLineFlash: c.judgeLineFlash,
                        currentCombo: c.currentCombo,
                      ),
                    );
                  },
                ),
              ),

              Positioned(
                top: padTop + (landscape ? 8 : 16),
                left: padLeft + 8,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: theme.colorScheme.primary,
                    size: landscape ? 20 : 24,
                  ),
                  onPressed: _handleExit,
                ),
              ),

              Positioned(
                top: padTop + (landscape ? 10 : 18),
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${c.score}/${c.highScore}',
                    style: TextStyle(
                      fontSize: landscape ? 18 : 24,
                      fontWeight: FontWeight.w200,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),

              Positioned(
                top: padTop + (landscape ? 8 : 16),
                right: MediaQuery.of(context).padding.right + 8,
                child: IconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: theme.colorScheme.primary,
                    size: landscape ? 20 : 24,
                  ),
                  onPressed: c.isExiting || c.isCountingDown
                      ? null
                      : () {
                          c.showSpeedSettings();
                          Navigator.of(context)
                              .push<void>(
                                MaterialPageRoute(
                                  builder: (context) => SpeedSettingsPage(
                                    primaryColor: theme.colorScheme.primary,
                                  ),
                                ),
                              )
                              .then((_) {
                                if (!mounted || c.isExiting) return;
                                c.reloadSettings().then((_) {
                                  if (c.isExiting) return;
                                  c.startCountdown();
                                });
                              });
                        },
                ),
              ),

              if (c.isCountingDown)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '${c.countdownValue}',
                      style: TextStyle(
                        fontSize: (landscape ? 80 : 120) * (landscape ? h : w) / 750,
                        fontWeight: FontWeight.w100,
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                ),

              if (_isWaterEntering)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _enterController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: WaterExitPainter(
                          progress: _enterController.value,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),

              if (c.isExiting)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _exitController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: WaterExitPainter(
                          progress: _exitController.value,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Public-facing widget that accepts ChartData parameter
class GamePage extends StatelessWidget {
  final ChartData chart;
  final String? audioPath;
  final String songId;

  const GamePage({
    super.key,
    required this.chart,
    this.audioPath,
    this.songId = '',
  });

  @override
  Widget build(BuildContext context) {
    return _LineDemoPage(
      chart: chart,
      audioPath: audioPath,
      songId: songId,
    );
  }
}
