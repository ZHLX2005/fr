import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/focus_session.dart';

enum TimerState { idle, running, paused }

class FocusTimerProvider extends ChangeNotifier {
  Timer? _timer;
  TimerState _state = TimerState.idle;
  int _totalSeconds = 0;
  DateTime? _sessionStartTime;

  static const String _timerStateKey = 'focus_timer_state';
  static const String _timerSecondsKey = 'focus_timer_seconds';
  static const String _timerStartTimeKey = 'focus_timer_start_time';

  TimerState get state => _state;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _state == TimerState.running;
  bool get isPaused => _state == TimerState.paused;
  bool get isIdle => _state == TimerState.idle;

  FocusTimerProvider() {
    _restoreTimerState();
  }

  Future<void> _restoreTimerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedState = prefs.getInt(_timerStateKey);
      final savedSeconds = prefs.getInt(_timerSecondsKey) ?? 0;
      final savedStartTimeStr = prefs.getString(_timerStartTimeKey);

      if (savedState == TimerState.running.index &&
          savedStartTimeStr != null) {
        final savedStartTime = DateTime.parse(savedStartTimeStr);
        _totalSeconds =
            savedSeconds + DateTime.now().difference(savedStartTime).inSeconds;
        _state = TimerState.running;
        _sessionStartTime = savedStartTime;
        _startInternalTimer();
        notifyListeners();
      } else if (savedState == TimerState.paused.index) {
        _totalSeconds = savedSeconds;
        _state = TimerState.paused;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('恢复计时器状态失败: $e');
    }
  }

  Future<void> _saveTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timerStateKey, _state.index);
    await prefs.setInt(_timerSecondsKey, _totalSeconds);
    if (_sessionStartTime != null) {
      await prefs.setString(
        _timerStartTimeKey,
        _sessionStartTime!.toIso8601String(),
      );
    } else {
      await prefs.remove(_timerStartTimeKey);
    }
  }

  Future<void> _clearTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_timerStateKey);
    await prefs.remove(_timerSecondsKey);
    await prefs.remove(_timerStartTimeKey);
  }

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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _totalSeconds++;
      notifyListeners();
    });
  }

  void pauseTimer() {
    if (_state != TimerState.running) return;
    _timer?.cancel();
    _state = TimerState.paused;
    _sessionStartTime = null;
    notifyListeners();
    _saveTimerState();
  }

  void resumeTimer() {
    if (_state != TimerState.paused) return;
    _state = TimerState.running;
    _sessionStartTime = DateTime.now();
    notifyListeners();
    _startInternalTimer();
    _saveTimerState();
  }

  void stopTimer() {
    _timer?.cancel();
    _state = TimerState.idle;
    _totalSeconds = 0;
    _sessionStartTime = null;
    notifyListeners();
    _clearTimerState();
  }

  void resetTimer() => stopTimer();

  /// 完成一次专注 — 返回会话记录供调用者保存（不再绑定任何 subject）。
  FocusSession? completeSession() {
    if (_totalSeconds == 0) return null;
    _timer?.cancel();
    _state = TimerState.idle;
    final durationMinutes = _totalSeconds ~/ 60;
    if (durationMinutes == 0) {
      resetTimer();
      return null;
    }
    final session = FocusSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      durationMinutes: durationMinutes,
      startTime: DateTime.now().subtract(Duration(seconds: _totalSeconds)),
      endTime: DateTime.now(),
      mode: FocusMode.freeTime,
    );
    resetTimer();
    return session;
  }

  String formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
