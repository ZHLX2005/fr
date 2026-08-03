import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/emphasis_button.dart';
import 'models/focus_session.dart';
import 'providers/focus_timer_provider.dart';
import 'providers/focus_provider.dart';

/// 专注计时器页面 - 心流空间（全屏极简模式）
class FocusTimerPage extends StatefulWidget {
  const FocusTimerPage({super.key});

  @override
  State<FocusTimerPage> createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends State<FocusTimerPage>
    with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _pulseController;
  final FocusTimerProvider _timerProvider = FocusTimerProvider();
  bool _showControls = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _pulseController.dispose();
    _hideTimer?.cancel();
    _timerProvider.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  String _formatCurrentTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatElapsed() {
    final seconds = _timerProvider.totalSeconds;
    final hour = seconds ~/ 3600;
    final minute = (seconds % 3600) ~/ 60;
    final second = seconds % 60;
    if (hour > 0) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
    }
    return '${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
  }

  String _formatDate() {
    final now = DateTime.now();
    final months = [
      '一月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '十一月',
      '十二月',
    ];
    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${months[now.month - 1]}${now.day}日 ${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final timeFontSize = screenWidth * 0.18;

    return ChangeNotifierProvider.value(
      value: _timerProvider,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF9F6),
        body: SafeArea(
          child: Stack(
            children: [
              // 空白区域点击 - 切换控制面板
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleControls,
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
              ),
              // 中央内容 - 可点击开始专注
              Center(
                child: Consumer<FocusTimerProvider>(
                  builder: (context, timer, child) {
                    return GestureDetector(
                      onTap: () {
                        if (timer.isIdle) {
                          timer.startTimer();
                          _pulseController.forward();
                        } else if (timer.isPaused) {
                          timer.resumeTimer();
                        }
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedOpacity(
                            opacity: _showControls ? 0.5 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _formatDate(),
                              style: TextStyle(
                                fontSize: screenWidth * 0.035,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedOpacity(
                            opacity: _showControls ? 0.3 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _formatCurrentTime(),
                              style: TextStyle(
                                fontSize: timeFontSize,
                                fontWeight: FontWeight.w100,
                                color: Colors.grey[700],
                                letterSpacing: -2,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildTimerDisplay(timer, timeFontSize),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // 顶部栏
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: _showControls ? 0 : -80,
                left: 0,
                right: 0,
                child: _buildTopBar(screenWidth),
              ),
              // 底部控制面板
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: _showControls ? 0 : -200,
                child: _buildBottomControls(screenWidth),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerDisplay(FocusTimerProvider timer, double fontSize) {
    final isRunning = timer.isRunning;
    final scale = isRunning ? (0.95 + _breathingController.value * 0.05) : 1.0;

    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        return Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatElapsed(),
                style: TextStyle(
                  fontSize: fontSize * 1.2,
                  fontWeight: FontWeight.w100,
                  color: const Color(0xFF7A9A6E),
                  letterSpacing: -4,
                  height: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _getTimerText(timer),
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getTimerText(FocusTimerProvider timer) {
    if (timer.isIdle) {
      return '点击开始专注';
    } else if (timer.isRunning) {
      return '专注中...';
    } else if (timer.isPaused) {
      return '已暂停';
    }
    return '';
  }

  Widget _buildTopBar(double screenWidth) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenWidth * 0.02,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.1), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.grey),
            onPressed: () {
              if (_showControls) {
                setState(() => _showControls = false);
                _hideTimer?.cancel();
              }
              Navigator.pop(context);
            },
          ),
          const Spacer(),
          const Text(
            '心流空间',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF7A9A6E),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildBottomControls(double screenWidth) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.06,
        vertical: screenWidth * 0.05,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Consumer<FocusTimerProvider>(
        builder: (context, timer, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.stop,
                    label: '退出',
                    color: Colors.grey[600]!,
                    onTap: () {
                      timer.stopTimer();
                      Navigator.pop(context);
                    },
                  ),
                  _buildActionButton(
                    icon: timer.isPaused ? Icons.play_arrow : Icons.pause,
                    label: timer.isPaused ? '继续' : '暂停',
                    color: const Color(0xFFD4AA96),
                    onTap: () {
                      if (timer.isPaused) {
                        timer.resumeTimer();
                      } else {
                        timer.pauseTimer();
                      }
                      _startHideTimer();
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.check_circle,
                    label: '完成',
                    color: const Color(0xFF7A9A6E),
                    onTap: () => _showEndConfirmDialog(context, timer),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        onTap();
        _startHideTimer();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showEndConfirmDialog(BuildContext context, FocusTimerProvider timer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '完成专注',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Color(0xFF7A9A6E),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '已专注 ${timer.totalSeconds ~/ 60} 分钟',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w200,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: EmphasisButton.ghostEmphasis(
                      context,
                      color: Colors.grey,
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      // await 之前先抓 focusProvider 与 session；await 之后
                      // 不再触碰 onTap 的 builder context（那是参数 context，
                      // 不是 State.context，lint 不接受它跨 await 用）。
                      Navigator.pop(context);
                      final focusProvider = Provider.of<FocusProvider>(
                        context,
                        listen: false,
                      );
                      final session = timer.completeSession();
                      if (session == null) return;
                      await focusProvider.addSession(session);
                      if (!mounted) return;
                      // 委托给 State 方法：使用 State.context（在 mounted 守卫下安全）。
                      _showCompletionDialog(session);
                    },
                    style: EmphasisButton.borderEmphasis(
                      context,
                      color: const Color(0xFF7A9A6E),
                    ),
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCompletionDialog(FocusSession session) {
    // 使用 State.context（受 mounted 守卫保护，避免跨 async gap 使用参数 context）。
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFFB5C9A3), size: 64),
            const SizedBox(height: 16),
            const Text(
              '专注完成',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '${session.durationMinutes} 分钟',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w200,
                color: Color(0xFFB5C9A3),
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: EmphasisButton.borderEmphasis(
              context,
              color: const Color(0xFFB5C9A3),
            ),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
