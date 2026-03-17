import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/lab_clock.dart';
import '../models/lab_clock_record.dart';

class LabClockProvider with ChangeNotifier {
  List<LabClock> _clocks = [];
  List<LabClockRecord> _records = [];
  static const String _storageKey = 'lab_clocks';
  static const String _recordsKey = 'lab_clock_records';
  Timer? _timer;
  String? _currentRecordId; // 当前正在进行的记录ID
  DateTime? _currentRecordSessionStart; // 当前记录本次会话的开始时间

  List<LabClock> get clocks => _clocks;
  List<LabClockRecord> get records => _records;

  LabClockProvider() {
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdowns();
    });
  }

  void _updateCountdowns() {
    bool hasChanges = false;
    for (int i = 0; i < _clocks.length; i++) {
      final clock = _clocks[i];
      if (clock.isRunning) {
        // 倒计时完成后继续负数运行，不停止
        _clocks[i] = clock.copyWith(remainingSeconds: clock.remainingSeconds - 1);
        hasChanges = true;
      }
    }
    if (hasChanges) {
      _saveClocks();
      notifyListeners();
    }
  }

  // 完成记录
  void _completeRecord(String clockId, {bool completed = false}) {
    if (_currentRecordId != null) {
      final index = _records.indexWhere((r) => r.id == _currentRecordId);
      if (index != -1) {
        final record = _records[index];
        final now = DateTime.now();

        // 计算本次会话的运行时间并累加
        int accumulated = record.accumulatedRunningSeconds;
        if (_currentRecordSessionStart != null) {
          accumulated += now.difference(_currentRecordSessionStart!).inSeconds;
        }

        _records[index] = record.copyWith(
          endTime: now,
          completed: completed,
          accumulatedRunningSeconds: accumulated,
        );
        _saveRecords();
      }
      _currentRecordId = null;
      _currentRecordSessionStart = null;
    }
  }

  Future<void> loadClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clocksJson = prefs.getString(_storageKey);
      if (clocksJson != null) {
        final List<dynamic> clocksList = json.decode(clocksJson);
        _clocks = clocksList.map((e) => LabClock.fromJson(e)).toList();

        // 根据startTime计算当前剩余时间
        final now = DateTime.now();
        for (int i = 0; i < _clocks.length; i++) {
          final clock = _clocks[i];
          if (clock.isRunning && clock.startTime != null) {
            final elapsed = now.difference(clock.startTime!).inSeconds;
            final newRemaining = (clock.durationSeconds ?? 0) - elapsed;
            if (newRemaining <= 0) {
              // 已过期
              _clocks[i] = clock.copyWith(isRunning: false, remainingSeconds: 0, startTime: null);
            } else {
              _clocks[i] = clock.copyWith(remainingSeconds: newRemaining);
            }
          }
        }
      }

      // 加载记录
      await loadRecords();

      notifyListeners();
    } catch (e) {
      debugPrint('加载时钟失败: $e');
    }
  }

  Future<void> loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = prefs.getString(_recordsKey);
      if (recordsJson != null) {
        final List<dynamic> recordsList = json.decode(recordsJson);
        _records = recordsList.map((e) => LabClockRecord.fromJson(e)).toList();
        // 按时间倒序
        _records.sort((a, b) => b.startTime.compareTo(a.startTime));
      }
    } catch (e) {
      debugPrint('加载记录失败: $e');
    }
  }

  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recordsJson = json.encode(_records.map((e) => e.toJson()).toList());
      await prefs.setString(_recordsKey, recordsJson);
    } catch (e) {
      debugPrint('保存记录失败: $e');
    }
  }

  Future<void> _saveClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clocksJson = json.encode(_clocks.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, clocksJson);
    } catch (e) {
      debugPrint('保存时钟失败: $e');
    }
  }

  Future<LabClock> createClock({
    String title = '新时钟',
    String description = '',
    String? targetTime,
    int? durationSeconds,
    String? color,
  }) async {
    final clock = LabClock(
      id: const Uuid().v4(),
      title: title,
      description: description,
      createdAt: DateTime.now(),
      targetTime: targetTime,
      durationSeconds: durationSeconds,
      isRunning: false,
      remainingSeconds: durationSeconds ?? 0,
      color: color ?? '#2196F3',
    );

    _clocks.insert(0, clock);
    await _saveClocks();
    notifyListeners();
    return clock;
  }

  Future<void> updateClock({
    required String id,
    String? title,
    String? description,
    String? targetTime,
    int? durationSeconds,
    String? color,
  }) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      _clocks[index] = clock.copyWith(
        title: title ?? clock.title,
        description: description ?? clock.description,
        targetTime: targetTime ?? clock.targetTime,
        durationSeconds: durationSeconds ?? clock.durationSeconds,
        color: color ?? clock.color,
      );
      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> startCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      final now = DateTime.now();

      // 如果时钟已经在运行，不做任何事
      if (clock.isRunning) {
        return;
      }

      // 检查是否已有此时钟的未完成记录（暂停后恢复）
      final existingRecordIndex = _records.indexWhere(
        (r) => r.clockId == id && r.endTime == null
      );

      if (existingRecordIndex != -1) {
        // 恢复现有记录
        _currentRecordId = _records[existingRecordIndex].id;
      } else {
        // 创建新记录
        final record = LabClockRecord(
          id: const Uuid().v4(),
          clockId: clock.id,
          clockTitle: clock.title,
          startTime: now,
          durationSeconds: clock.durationSeconds ?? 0,
        );
        _records.insert(0, record);
        _currentRecordId = record.id;
        await _saveRecords();
      }

      // 记录本次会话开始时间（用于累加运行时间）
      _currentRecordSessionStart = now;

      _clocks[index] = clock.copyWith(
        isRunning: true,
        remainingSeconds: clock.durationSeconds ?? 0,
        startTime: now,
      );

      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> pauseCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      // 只是暂停，不完成记录
      _clocks[index] = clock.copyWith(isRunning: false);

      // 累加本次会话的运行时间到记录中
      if (_currentRecordId != null && _currentRecordSessionStart != null) {
        // 确认是此时钟的记录
        final recordIndex = _records.indexWhere((r) => r.id == _currentRecordId && r.clockId == id);
        if (recordIndex != -1) {
          final record = _records[recordIndex];
          final elapsed = DateTime.now().difference(_currentRecordSessionStart!).inSeconds;
          _records[recordIndex] = record.copyWith(
            accumulatedRunningSeconds: record.accumulatedRunningSeconds + elapsed,
          );
          await _saveRecords();
        }
        _currentRecordSessionStart = null;  // 清除会话开始时间
      }

      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> resetCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      _clocks[index] = clock.copyWith(
        isRunning: false,
        remainingSeconds: clock.durationSeconds ?? 0,
      );

      // 重置时完成记录
      _completeRecord(id, completed: true);

      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> updateTime(String id, int newDurationSeconds) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      final wasRunning = clock.isRunning;
      _clocks[index] = clock.copyWith(
        durationSeconds: newDurationSeconds,
        // 如果时钟正在运行且新时间不为负，调整remainingSeconds
        remainingSeconds: wasRunning && newDurationSeconds >= 0
            ? newDurationSeconds
            : clock.remainingSeconds,
      );
      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> deleteClock(String id) async {
    _clocks.removeWhere((c) => c.id == id);
    await _saveClocks();
    notifyListeners();
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _saveRecords();
    notifyListeners();
  }

  Future<void> clearRecords() async {
    _records.clear();
    await _saveRecords();
    notifyListeners();
  }

  LabClock? getClockById(String id) {
    try {
      return _clocks.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
