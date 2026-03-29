import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/focus_session.dart';
import '../models/focus_subject.dart';

/// 计时器状态
enum TimerState {
  idle, // 空闲
  running, // 运行中
  paused, // 已暂停
}

/// 专注计时器Provider - 仅支持自由计时模式
class FocusTimerProvider extends ChangeNotifier {
  Timer? _timer;
  TimerState _state = TimerState.idle;
  FocusSubject? _selectedSubject;
  int _totalSeconds = 0; // 累计秒数

  // Getters
  TimerState get state => _state;
  FocusSubject? get selectedSubject => _selectedSubject;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _state == TimerState.running;
  bool get isPaused => _state == TimerState.paused;
  bool get isIdle => _state == TimerState.idle;

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

    // 累加计时
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _totalSeconds++;
      notifyListeners();
    });
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
    _totalSeconds = 0;
    notifyListeners();
  }

  /// 完成一次专注 - 返回会话记录供调用者保存
  FocusSession? completeSession() {
    if (_totalSeconds == 0) return null;

    _timer?.cancel();
    _state = TimerState.idle;

    final durationMinutes = _totalSeconds ~/ 60;
    if (durationMinutes == 0) {
      resetTimer();
      return null;
    }

    // 创建专注记录
    final session = FocusSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      subjectId: _selectedSubject?.id ?? 'default',
      durationMinutes: durationMinutes,
      startTime: DateTime.now().subtract(Duration(seconds: _totalSeconds)),
      endTime: DateTime.now(),
      mode: FocusMode.freeTime,
    );

    final savedSession = session;
    resetTimer();
    return savedSession;
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
