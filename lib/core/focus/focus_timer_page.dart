import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/focus_session.dart';
import 'models/focus_subject.dart';
import 'providers/focus_timer_provider.dart';
import 'providers/focus_provider.dart' as data;

/// 专注计时器页面 - 心流空间（全屏极简模式）
class FocusTimerPage extends StatefulWidget {
  final FocusSubject? initialSubject;

  const FocusTimerPage({super.key, this.initialSubject});

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

    if (widget.initialSubject != null) {
      _timerProvider.selectSubject(widget.initialSubject);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final focusProvider =
            Provider.of<data.FocusProvider>(context, listen: false);
        focusProvider.restoreTimerState(_timerProvider);
      }
    });
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
    final second = now.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
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
      '一月', '二月', '三月', '四月', '五月', '六月',
      '七月', '八月', '九月', '十月', '十一月', '十二月'
    ];
    final weekdays = [
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'
    ];
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
              // 空白区域点击
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleControls,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
              // 中央内容
              Center(
                child: Consumer<FocusTimerProvider>(
                  builder: (context, timer, child) {
                    return Column(
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
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
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
          colors: [
            Colors.black.withValues(alpha: 0.1),
            Colors.transparent,
          ],
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
          IconButton(
            icon: const Icon(Icons.category_outlined, color: Colors.grey),
            onPressed: () => _showSubjectSelector(context),
          ),
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
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
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

  void _showSubjectSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择学习领域',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: Consumer<data.FocusProvider>(
                builder: (context, focusProvider, child) {
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: focusProvider.subjects.length + 1,
                    itemBuilder: (context, index) {
                      if (index == focusProvider.subjects.length) {
                        return ListTile(
                          leading: Icon(Icons.add_circle_outline,
                              color: Colors.grey[600]),
                          title: const Text('添加新领域'),
                          onTap: () => Navigator.pop(context),
                        );
                      }
                      final subject = focusProvider.subjects[index];
                      final isSelected =
                          _timerProvider.selectedSubject?.id == subject.id;
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: subject.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(subject.icon, color: subject.color),
                        ),
                        title: Text(subject.name),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: subject.color)
                            : null,
                        onTap: () {
                          _timerProvider.selectSubject(subject);
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEndConfirmDialog(
      BuildContext context, FocusTimerProvider timer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('完成专注'),
        content: Text('已专注 ${timer.totalSeconds ~/ 60} 分钟，确定完成吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final session = timer.completeSession();
              if (session != null && context.mounted) {
                final focusProvider = context.read<data.FocusProvider>();
                await focusProvider.addSession(session);
                if (mounted) {
                  _showCompletionDialog(context, session);
                }
              }
            },
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog(BuildContext context, FocusSession session) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFFB5C9A3), size: 64),
            const SizedBox(height: 16),
            const Text('专注完成',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
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
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB5C9A3),
            ),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
