import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/focus_session.dart';
import '../models/focus_subject.dart';

/// 计时器状态
enum TimerState {
  idle, // 空闲
  running, // 运行中
  paused, // 已暂停
}

/// 专注计时器Provider - 支持后台计时的自由计时模式
class FocusTimerProvider extends ChangeNotifier {
  Timer? _timer;
  TimerState _state = TimerState.idle;
  FocusSubject? _selectedSubject;
  int _totalSeconds = 0; // 累计秒数

  // 后台计时支持
  DateTime? _sessionStartTime; // 本次计时开始时间（用于后台恢复）
  static const String _timerStateKey = 'focus_timer_state';
  static const String _timerSecondsKey = 'focus_timer_seconds';
  static const String _timerSubjectKey = 'focus_timer_subject';
  static const String _timerStartTimeKey = 'focus_timer_start_time';

  // Getters
  TimerState get state => _state;
  FocusSubject? get selectedSubject => _selectedSubject;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _state == TimerState.running;
  bool get isPaused => _state == TimerState.paused;
  bool get isIdle => _state == TimerState.idle;

  FocusTimerProvider() {
    _restoreTimerState();
  }

  /// 从持久化存储恢复计时器状态
  Future<void> _restoreTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedState = prefs.getInt(_timerStateKey);
      final savedSeconds = prefs.getInt(_timerSecondsKey) ?? 0;
      final savedSubjectId = prefs.getString(_timerSubjectKey);
      final savedStartTimeStr = prefs.getString(_timerStartTimeKey);

      if (savedState == TimerState.running.index && savedStartTimeStr != null) {
        // 恢复运行中的计时器
        final savedStartTime = DateTime.parse(savedStartTimeStr);
        final elapsedSinceSave = DateTime.now().difference(savedStartTime).inSeconds;

        _totalSeconds = savedSeconds + elapsedSinceSave;
        _state = TimerState.running;
        _sessionStartTime = savedStartTime;

        // 恢复科目
        // 注意：科目需要在外部通过 selectSubject 恢复

        // 继续计时
        _startInternalTimer();
        notifyListeners();
      } else if (savedState == TimerState.paused.index) {
        // 恢复暂停状态
        _totalSeconds = savedSeconds;
        _state = TimerState.paused;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('恢复计时器状态失败: $e');
    }
  }

  /// 保存计时器状态到持久化存储
  Future<void> _saveTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt(_timerStateKey, _state.index);
      await prefs.setInt(_timerSecondsKey, _totalSeconds);
      if (_selectedSubject != null) {
        await prefs.setString(_timerSubjectKey, _selectedSubject!.id);
      } else {
        await prefs.remove(_timerSubjectKey);
      }
      if (_sessionStartTime != null) {
        await prefs.setString(_timerStartTimeKey, _sessionStartTime!.toIso8601String());
      } else {
        await prefs.remove(_timerStartTimeKey);
      }
    } catch (e) {
      debugPrint('保存计时器状态失败: $e');
    }
  }

  /// 清除持久化的计时器状态
  Future<void> _clearTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_timerStateKey);
      await prefs.remove(_timerSecondsKey);
      await prefs.remove(_timerSubjectKey);
      await prefs.remove(_timerStartTimeKey);
    } catch (e) {
      debugPrint('清除计时器状态失败: $e');
    }
  }

  /// 选择科目
  void selectSubject(FocusSubject? subject) {
    _selectedSubject = subject;
    notifyListeners();
  }

  /// 恢复科目（根据ID）
  void restoreSubject(FocusSubject? subject) {
    _selectedSubject = subject;
    notifyListeners();
  }

  /// 开始计时
  void startTimer() {
    if (_state == TimerState.running) return;

    _state = TimerState.running;
    _sessionStartTime = DateTime.now();
    notifyListeners();

    _startInternalTimer();
    _saveTimerState();
  }

  void _startInternalTimer() {
    _timer?.cancel();
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
    _sessionStartTime = null;
    notifyListeners();

    _saveTimerState();
  }

  /// 恢复计时
  void resumeTimer() {
    if (_state != TimerState.paused) return;

    _state = TimerState.running;
    _sessionStartTime = DateTime.now();
    notifyListeners();

    _startInternalTimer();
    _saveTimerState();
  }

  /// 停止计时
  void stopTimer() {
    _timer?.cancel();
    _state = TimerState.idle;
    _totalSeconds = 0;
    _sessionStartTime = null;
    notifyListeners();

    _clearTimerState();
  }

  /// 重置计时器
  void resetTimer() {
    stopTimer();
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