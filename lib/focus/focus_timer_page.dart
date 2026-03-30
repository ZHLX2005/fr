import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/focus_session.dart';
import 'models/focus_subject.dart';
import 'providers/focus_timer_provider.dart';
import 'providers/focus_provider.dart' as data;

/// 专注计时器页面 - 心流空间（简化版 - 仅自由计时）
class FocusTimerPage extends StatefulWidget {
  final FocusSubject? initialSubject;

  const FocusTimerPage({super.key, this.initialSubject});

  @override
  State<FocusTimerPage> createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends State<FocusTimerPage> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _pulseController;
  final FocusTimerProvider _timerProvider = FocusTimerProvider();

  @override
  void initState() {
    super.initState();

    // 呼吸动画（4秒一个周期）
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // 脉冲动画
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 设置初始科目
    if (widget.initialSubject != null) {
      _timerProvider.selectSubject(widget.initialSubject);
    }

    // 恢复计时器状态（如果之前有正在计时的会话）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final focusProvider = Provider.of<data.FocusProvider>(context, listen: false);
        focusProvider.restoreTimerState(_timerProvider);
      }
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _pulseController.dispose();
    _timerProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _timerProvider,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF9F6),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Consumer<FocusTimerProvider>(
                  builder: (context, timer, child) {
                    return Stack(
                      children: [
                        _buildBackground(timer),
                        _buildContent(timer),
                      ],
                    );
                  },
                ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部栏
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          const Text(
            '心流空间',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF5C8B5E),
            ),
          ),
          const Spacer(),
          Consumer<FocusTimerProvider>(
            builder: (context, timer, child) {
              return IconButton(
                icon: const Icon(Icons.palette_outlined),
                onPressed: () => _showSubjectSelector(context, timer),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 背景动效
  Widget _buildBackground(FocusTimerProvider timer) {
    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2 + _breathingController.value * 0.3,
              colors: [
                const Color(0xFF9CAF88).withValues(alpha: 0.1),
                const Color(0xFFFAF9F6),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 主要内容
  Widget _buildContent(FocusTimerProvider timer) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (timer.selectedSubject != null)
            _buildSubjectInfo(timer.selectedSubject!),
          const SizedBox(height: 32),
          _buildTimerDisplay(timer),
        ],
      ),
    );
  }

  /// 科目信息
  Widget _buildSubjectInfo(FocusSubject subject) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: subject.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subject.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            subject.name,
            style: TextStyle(
              color: subject.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 计时器显示 - 可点击启动
  Widget _buildTimerDisplay(FocusTimerProvider timer) {
    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        final scale = timer.isRunning
            ? (0.95 + _breathingController.value * 0.1)
            : 1.0;

        return GestureDetector(
          onTap: () {
            if (timer.isIdle) {
              timer.startTimer();
              _pulseController.forward();
            } else if (timer.isPaused) {
              timer.resumeTimer();
            }
          },
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF9CAF88),
                    const Color(0xFFB5C9A3),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9CAF88).withValues(alpha: 0.3),
                    offset: const Offset(0, 8),
                    blurRadius: 32 + _breathingController.value * 16,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      timer.formatTime(timer.totalSeconds),
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w200,
                        color: Colors.white,
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getTimerText(timer),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getTimerText(FocusTimerProvider timer) {
    if (timer.isIdle) {
      return '点击圆环开始专注';
    } else if (timer.isRunning) {
      return '专注中...';
    } else if (timer.isPaused) {
      return '已暂停 - 点击继续';
    }
    return '';
  }

  /// 底部控制栏
  Widget _buildControls() {
    return Consumer<FocusTimerProvider>(
      builder: (context, timer, child) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!timer.isIdle) ...[
                  _buildControlButton(
                    icon: timer.isPaused ? Icons.play_arrow : Icons.pause,
                    label: timer.isPaused ? '继续' : '暂停',
                    onTap: timer.isPaused ? timer.resumeTimer : timer.pauseTimer,
                  ),
                  const SizedBox(width: 16),
                  _buildControlButton(
                    icon: Icons.stop,
                    label: '完成',
                    isDestructive: true,
                    onTap: () => _showEndConfirmDialog(context, timer),
                  ),
                ] else
                  _buildStartButton(timer),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.grey[300]
              : const Color(0xFF9CAF88),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.grey[700] : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isDestructive ? Colors.grey[700] : Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 开始按钮
  Widget _buildStartButton(FocusTimerProvider timer) {
    return GestureDetector(
      onTap: () {
        timer.startTimer();
        _pulseController.forward();
      },
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + _pulseController.value * 0.05,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF9CAF88),
                    Color(0xFFB5C9A3),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9CAF88).withValues(alpha: 0.4),
                    offset: const Offset(0, 8),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.play_arrow, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    '开始专注',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 科目选择器
  void _showSubjectSelector(BuildContext context, FocusTimerProvider timer) {
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
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
                          leading: const Icon(Icons.add_circle_outline),
                          title: const Text('添加新领域'),
                          onTap: () {
                            Navigator.pop(context);
                            // TODO: 显示添加科目对话框
                          },
                        );
                      }

                      final subject = focusProvider.subjects[index];
                      final isSelected = timer.selectedSubject?.id == subject.id;

                      return ListTile(
                        leading: Text(subject.icon, style: const TextStyle(fontSize: 24)),
                        title: Text(subject.name),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF9CAF88)) : null,
                        onTap: () {
                          timer.selectSubject(subject);
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

  /// 结束确认对话框
  void _showEndConfirmDialog(BuildContext context, FocusTimerProvider timer) {
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

              // 完成会话并保存到 FocusProvider
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

  /// 完成对话框
  void _showCompletionDialog(BuildContext context, FocusSession session) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              color: Color(0xFF9CAF88),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              '专注完成',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${session.durationMinutes} 分钟',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w200,
                color: Color(0xFF9CAF88),
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
              backgroundColor: const Color(0xFF9CAF88),
            ),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
