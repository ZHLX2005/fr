import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/focus_subject.dart';
import 'providers/focus_provider.dart' as data;

/// 全屏顺序计时器页面
class FullscreenTimerPage extends StatefulWidget {
  const FullscreenTimerPage({super.key});

  @override
  State<FullscreenTimerPage> createState() => _FullscreenTimerPageState();
}

class _FullscreenTimerPageState extends State<FullscreenTimerPage>
    with TickerProviderStateMixin {
  // 计时段落列表
  final List<TimeSegment> _segments = [];

  // 当前正在计时的段落索引
  int _currentSegmentIndex = -1;

  // 计时器
  Timer? _timer;

  // 动画控制器
  late AnimationController _pulseController;
  late AnimationController _progressController;

  // 是否全屏
  bool _isFullscreen = false;

  // 是否已初始化默认时段
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  void _addDefaultSegments() {
    if (_isInitialized) return;

    // 使用 addPostFrameCallback 确保 context 已准备好
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isInitialized) return;

      final focusProvider = Provider.of<data.FocusProvider>(context, listen: false);
      if (focusProvider.subjects.isNotEmpty) {
        // 添加前三个科目作为默认时段
        for (int i = 0; i < focusProvider.subjects.length && i < 3; i++) {
          _segments.add(TimeSegment(
            subject: focusProvider.subjects[i],
            durationMinutes: 25,
          ));
        }
      } else {
        // 如果没有科目，添加默认时段
        _segments.add(TimeSegment(
          subject: FocusSubject(
            id: 'default',
            name: '时段1',
            icon: '⏱️',
            color: const Color(0xFF9CAF88),
          ),
          durationMinutes: 25,
        ));
      }
      _isInitialized = true;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _progressController.dispose();
    // 退出时恢复系统UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  /// 进入全屏
  void _enterFullscreen() {
    setState(() {
      _isFullscreen = true;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 退出全屏
  void _exitFullscreen() {
    setState(() {
      _isFullscreen = false;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  /// 开始计时
  void _startTimer() {
    if (_segments.isEmpty || _currentSegmentIndex >= 0) return;

    _currentSegmentIndex = 0;
    _startCurrentSegment();
  }

  /// 开始当前时段
  void _startCurrentSegment() {
    if (_currentSegmentIndex < 0 || _currentSegmentIndex >= _segments.length) {
      _finishAll();
      return;
    }

    final segment = _segments[_currentSegmentIndex];
    segment.state = SegmentState.running;
    segment.startTime = DateTime.now();
    setState(() {});

    _progressController.forward(from: 0);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final elapsed = DateTime.now().difference(segment.startTime!).inSeconds;
      segment.elapsedSeconds = elapsed;

      // 检查是否完成
      if (elapsed >= segment.durationMinutes * 60) {
        _completeCurrentSegment();
      } else {
        setState(() {});
      }
    });
  }

  /// 完成当前时段
  void _completeCurrentSegment() {
    _timer?.cancel();
    final segment = _segments[_currentSegmentIndex];
    segment.state = SegmentState.completed;

    // 自动进入下一个时段
    if (_currentSegmentIndex < _segments.length - 1) {
      _currentSegmentIndex++;
      Future.delayed(const Duration(seconds: 1), () {
        _startCurrentSegment();
      });
    } else {
      _finishAll();
    }
    setState(() {});
  }

  /// 完成所有时段
  void _finishAll() {
    _timer?.cancel();
    _currentSegmentIndex = -1;
    for (var segment in _segments) {
      if (segment.state != SegmentState.completed) {
        segment.state = SegmentState.pending;
      }
    }
    setState(() {});

    // 显示完成对话框
    if (mounted) {
      _showCompletionDialog();
    }
  }

  /// 暂停计时
  void _pauseTimer() {
    _timer?.cancel();
    if (_currentSegmentIndex >= 0 && _currentSegmentIndex < _segments.length) {
      _segments[_currentSegmentIndex].state = SegmentState.paused;
      setState(() {});
    }
  }

  /// 恢复计时
  void _resumeTimer() {
    if (_currentSegmentIndex >= 0 && _currentSegmentIndex < _segments.length) {
      _startCurrentSegment();
    }
  }

  /// 停止计时
  void _stopTimer() {
    _timer?.cancel();
    _currentSegmentIndex = -1;
    for (var segment in _segments) {
      segment.state = SegmentState.pending;
      segment.elapsedSeconds = 0;
      segment.startTime = null;
    }
    setState(() {});
  }

  /// 显示完成对话框
  void _showCompletionDialog() {
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
              '全部完成！',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '共完成 ${_segments.length} 个时段',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exitFullscreen();
              Navigator.pop(context);
            },
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _stopTimer();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9CAF88),
            ),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 首次构建时添加默认时段
    _addDefaultSegments();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏（全屏时隐藏）
            if (!_isFullscreen) _buildHeader(),
            // 主内容
            Expanded(
              child: _buildContent(),
            ),
            // 底部控制栏
            _buildControls(),
          ],
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
            '顺序计时',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF5C8B5E),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: _isFullscreen ? _exitFullscreen : _enterFullscreen,
          ),
        ],
      ),
    );
  }

  /// 主内容
  Widget _buildContent() {
    if (_currentSegmentIndex >= 0 && _currentSegmentIndex < _segments.length) {
      return _buildRunningTimer();
    }
    return _buildSegmentsList();
  }

  /// 运行中的计时器
  Widget _buildRunningTimer() {
    final segment = _segments[_currentSegmentIndex];
    final progress = segment.elapsedSeconds / (segment.durationMinutes * 60);
    final remainingSeconds = segment.durationMinutes * 60 - segment.elapsedSeconds;

    return Container(
      color: segment.subject.color.withValues(alpha: 0.1),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 时段信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: segment.subject.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    segment.subject.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    segment.subject.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: segment.subject.color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // 进度圆环
            SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 背景圆环
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: segment.subject.color.withValues(alpha: 0.15),
                    ),
                  ),
                  // 进度圆环
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        backgroundColor: segment.subject.color.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(segment.subject.color),
                      );
                    },
                  ),
                  // 时间显示
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatTime(remainingSeconds),
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w200,
                          color: segment.subject.color,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '剩余时间',
                        style: TextStyle(
                          fontSize: 14,
                          color: segment.subject.color.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // 进度提示
            Text(
              '第 ${_currentSegmentIndex + 1} / ${_segments.length} 个时段',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 时段列表
  Widget _buildSegmentsList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 总计信息
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9CAF88), Color(0xFFB5C9A3)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '总计时长',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_segments.fold<int>(0, (sum, s) => sum + s.durationMinutes)} 分钟',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w200,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_segments.length} 个时段',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 时段列表
          ...List.generate(_segments.length, (index) {
            return _buildSegmentCard(index);
          }),

          // 添加时段按钮
          const SizedBox(height: 16),
          InkWell(
            onTap: _showAddSegmentDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: Color(0xFF9CAF88)),
                  SizedBox(width: 8),
                  Text(
                    '添加时段',
                    style: TextStyle(
                      color: Color(0xFF9CAF88),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 时段卡片
  Widget _buildSegmentCard(int index) {
    final segment = _segments[index];
    final elapsed = segment.elapsedSeconds;
    final total = segment.durationMinutes * 60;
    final progress = elapsed > 0 ? elapsed / total : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: segment.subject.color.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          // 序号
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: segment.subject.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: segment.subject.color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 科目信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(segment.subject.icon),
                    const SizedBox(width: 4),
                    Text(
                      segment.subject.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${segment.durationMinutes} 分钟',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // 已用时间
          if (elapsed > 0)
            Text(
              _formatTime(elapsed),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: segment.subject.color,
              ),
            ),

          // 删除按钮
          if (_currentSegmentIndex < 0)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.grey,
              onPressed: () {
                setState(() {
                  _segments.removeAt(index);
                });
              },
            ),
        ],
      ),
    );
  }

  /// 底部控制栏
  Widget _buildControls() {
    final hasRunning = _currentSegmentIndex >= 0;
    final currentSegment = _currentSegmentIndex >= 0 && _currentSegmentIndex < _segments.length
        ? _segments[_currentSegmentIndex]
        : null;

    return Container(
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!hasRunning && _segments.isNotEmpty)
              _buildControlButton(
                icon: Icons.play_arrow,
                label: '开始',
                onTap: _startTimer,
              ),
            if (hasRunning && currentSegment?.state == SegmentState.running)
              _buildControlButton(
                icon: Icons.pause,
                label: '暂停',
                onTap: _pauseTimer,
              ),
            if (hasRunning && currentSegment?.state == SegmentState.paused)
              _buildControlButton(
                icon: Icons.play_arrow,
                label: '继续',
                onTap: _resumeTimer,
              ),
            if (hasRunning) ...[
              const SizedBox(width: 16),
              _buildControlButton(
                icon: Icons.stop,
                label: '停止',
                isDestructive: true,
                onTap: _stopTimer,
              ),
            ],
          ],
        ),
      ),
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
          gradient: isDestructive
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF9CAF88), Color(0xFFB5C9A3)],
                ),
          color: isDestructive ? Colors.grey[300] : null,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isDestructive
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF9CAF88).withValues(alpha: 0.3),
                    offset: const Offset(0, 4),
                    blurRadius: 16,
                  ),
                ],
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

  /// 添加时段对话框
  void _showAddSegmentDialog() {
    showDialog(
      context: context,
      builder: (context) => Consumer<data.FocusProvider>(
        builder: (context, focusProvider, child) => AlertDialog(
          title: const Text('添加时段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择科目'),
              const SizedBox(height: 16),
              ...focusProvider.subjects.map((subject) {
                return ListTile(
                  leading: Text(subject.icon, style: const TextStyle(fontSize: 24)),
                  title: Text(subject.name),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _segments.add(TimeSegment(
                        subject: subject,
                        durationMinutes: 25,
                      ));
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化时间
  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// 时段状态
enum SegmentState {
  pending, // 等待中
  running, // 运行中
  paused, // 已暂停
  completed, // 已完成
}

/// 计时段落
class TimeSegment {
  FocusSubject subject;
  int durationMinutes;
  int elapsedSeconds;
  SegmentState state;
  DateTime? startTime;

  TimeSegment({
    required this.subject,
    required this.durationMinutes,
    this.elapsedSeconds = 0,
    this.state = SegmentState.pending,
    this.startTime,
  });
}
