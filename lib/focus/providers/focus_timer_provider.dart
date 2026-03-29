import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/focus_session.dart';
import '../models/focus_subject.dart';

/// 计时器状态
enum TimerState {
  idle, // 空闲
  running, // 运行中
  paused, // 已暂停
  completed, // 已完成
}

/// 计时器Provider
class FocusTimerProvider extends ChangeNotifier {
  Timer? _timer;
  TimerState _state = TimerState.idle;
  FocusMode _mode = FocusMode.pomodoro;
  FocusSubject? _selectedSubject;
  int _remainingSeconds = 25 * 60; // 默认25分钟
  int _totalSeconds = 25 * 60;
  int _completedSessions = 0;
  final List<FocusSession> _sessions = [];

  // Getters
  TimerState get state => _state;
  FocusMode get mode => _mode;
  FocusSubject? get selectedSubject => _selectedSubject;
  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  double get progress => _totalSeconds > 0 ? (_totalSeconds - _remainingSeconds) / _totalSeconds : 0;
  int get completedSessions => _completedSessions;
  List<FocusSession> get sessions => List.unmodifiable(_sessions);
  bool get isRunning => _state == TimerState.running;
  bool get isPaused => _state == TimerState.paused;
  bool get isIdle => _state == TimerState.idle;

  /// 设置专注模式
  void setMode(FocusMode mode) {
    _mode = mode;
    if (_state == TimerState.idle) {
      if (mode == FocusMode.pomodoro) {
        _totalSeconds = 25 * 60;
        _remainingSeconds = 25 * 60;
      } else {
        _totalSeconds = 0;
        _remainingSeconds = 0;
      }
    }
    notifyListeners();
  }

  /// 选择科目
  void selectSubject(FocusSubject? subject) {
    _selectedSubject = subject;
    notifyListeners();
  }

  /// 开始计时
  void startTimer() {
    if (_state == TimerState.running) return;

    _state = TimerState.running;
    notifyListeners();

    if (_mode == FocusMode.freeTime) {
      // 自由计时模式：累加计时
      _totalSeconds = 0;
      _remainingSeconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _totalSeconds++;
        _remainingSeconds = _totalSeconds;
        notifyListeners();
      });
    } else {
      // 番茄钟模式：倒计时
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          notifyListeners();
        } else {
          completeSession();
        }
      });
    }
  }

  /// 暂停计时
  void pauseTimer() {
    if (_state != TimerState.running) return;

    _timer?.cancel();
    _state = TimerState.paused;
    notifyListeners();
  }

  /// 恢复计时
  void resumeTimer() {
    if (_state != TimerState.paused) return;
    startTimer();
  }

  /// 停止计时
  void stopTimer() {
    _timer?.cancel();
    _state = TimerState.idle;
    notifyListeners();
  }

  /// 重置计时器
  void resetTimer() {
    stopTimer();
    if (_mode == FocusMode.pomodoro) {
      _totalSeconds = 25 * 60;
      _remainingSeconds = 25 * 60;
    } else {
      _totalSeconds = 0;
      _remainingSeconds = 0;
    }
    notifyListeners();
  }

  /// 完成一次专注
  void completeSession() {
    _timer?.cancel();
    _state = TimerState.completed;

    // 创建专注记录
    final session = FocusSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      subjectId: _selectedSubject?.id ?? 'default',
      durationMinutes: _mode == FocusMode.pomodoro ? 25 : (_totalSeconds ~/ 60),
      startTime: DateTime.now().subtract(Duration(minutes: _mode == FocusMode.pomodoro ? 25 : (_totalSeconds ~/ 60))),
      endTime: DateTime.now(),
      mode: _mode,
    );

    _sessions.add(session);
    _completedSessions++;

    notifyListeners();

    // 延迟后重置
    Future.delayed(const Duration(seconds: 2), () {
      if (_state == TimerState.completed) {
        resetTimer();
      }
    });
  }

  /// 格式化时间显示
  String formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 获取今日总学时（分钟）
  int getTodayMinutes() {
    final today = DateTime.now();
    return _sessions
        .where((session) =>
            session.startTime.year == today.year &&
            session.startTime.month == today.month &&
            session.startTime.day == today.day)
        .fold<int>(0, (sum, session) => sum + session.durationMinutes);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
