import 'package:flutter/material.dart';
import '../../domain/chart_data.dart';
import '../../domain/game_result.dart';
import '../painters/game_painter.dart';
import '../painters/water_effect_painter.dart';
import '../../game_controller.dart';
import 'game_result_page.dart';
import 'song_select_page.dart';
import '../../settings/line_settings.dart';

class _LineDemoPage extends StatefulWidget {
  final ChartData chart;
  final String? audioPath;

  const _LineDemoPage({required this.chart, this.audioPath});

  @override
  State<_LineDemoPage> createState() => _LineDemoPageState();
}

class _LineDemoPageState extends State<_LineDemoPage>
    with TickerProviderStateMixin {
  // ── 水入场动画（UI 专属，非游戏逻辑） ──
  bool _isWaterEntering = true;

  late AnimationController _exitController;
  late AnimationController _enterController;
  late AnimationController _healthController;
  late AnimationController _renderTicker;

  late final GameController _controller;

  @override
  void initState() {
    super.initState();

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

    final screenSize = MediaQuery.of(context).size;

    _controller = GameController(
      chart: widget.chart,
      audioPath: widget.audioPath,
      vsync: this,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      themeColor: Theme.of(context).colorScheme.primary,
      onGameOver: _onGameOver,
    )..onStateChanged = () {
        if (mounted) setState(() {});
      };
    _controller.init();

    _enterController.value = 1.0;
    _enterController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _isWaterEntering = false);
      _controller.startCountdown();
    });
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
    final colWidth = w / GameController.columnCount;
    final radius = colWidth * GameController.noteSizeRatio;
    final judgeY = h * GameController.judgeLineRatio;

    final c = _controller;

    final allControllers = <AnimationController>[];
    for (final col in c.notes) {
      for (final note in col) {
        allControllers.add(note.controller);
      }
    }
    for (final e in c.explodes) {
      allControllers.add(e.controller);
    }
    for (final fb in c.judgeFeedbacks) {
      allControllers.add(fb.controller);
    }
    allControllers.add(_healthController);
    allControllers.add(_renderTicker);

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
            c.handlePointerDown(e);
            setState(() {});
          },
          onPointerMove: c.handlePointerMove,
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
              // ── 游戏渲染 ──
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge(allControllers),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: GamePainter(
                        columns: c.notes,
                        explodes: c.explodes,
                        color: theme.colorScheme.primary,
                        radius: radius,
                        screenWidth: w,
                        screenHeight: h,
                        columnCount: GameController.columnCount,
                        judgeY: judgeY,
                        judgeFeedbacks: c.judgeFeedbacks,
                        backgroundStyle: c.backgroundStyle,
                        health: c.health,
                        dropDuration: widget.chart.dropDuration.toDouble(),
                        scrollSpeed: c.scrollSpeed,
                        gameElapsed: c.gameStopwatch.elapsedMilliseconds,
                      ),
                    );
                  },
                ),
              ),

              // ── 返回按钮 ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  onPressed: _handleExit,
                ),
              ),

              // ── 分数 ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${c.score}/${c.highScore}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w200,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      fontFeatures: [const FontFeature.tabularFigures()],
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),

              // ── 设置按钮 ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: IconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: theme.colorScheme.primary,
                    size: 24,
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

              // ── 倒计时 ──
              if (c.isCountingDown)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '${c.countdownValue}',
                      style: TextStyle(
                        fontSize: 120 * w / 750,
                        fontWeight: FontWeight.w100,
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                ),

              // ── 水入场动画 ──
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

              // ── 水退场动画 ──
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

  const GamePage({super.key, required this.chart, this.audioPath});

  @override
  Widget build(BuildContext context) {
    return _LineDemoPage(chart: chart, audioPath: audioPath);
  }
}
