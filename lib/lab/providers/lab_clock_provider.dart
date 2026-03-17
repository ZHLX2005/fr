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
        // 倒计时完成后继续负数运行
        _clocks[i] = clock.copyWith(remainingSeconds: clock.remainingSeconds - 1);
        hasChanges = true;
      }
    }
    if (hasChanges) {
      _saveClocks();
      notifyListeners();
    }
  }

  Future<void> loadClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clocksJson = prefs.getString(_storageKey);
      if (clocksJson != null) {
        final List<dynamic> clocksList = json.decode(clocksJson);
        _clocks = clocksList.map((e) => LabClock.fromJson(e)).toList();

        final now = DateTime.now();
        for (int i = 0; i < _clocks.length; i++) {
          final clock = _clocks[i];
          if (clock.isRunning && clock.startTime != null) {
            final elapsed = now.difference(clock.startTime!).inSeconds;
            final newRemaining = (clock.durationSeconds ?? 0) - elapsed;
            _clocks[i] = clock.copyWith(
              remainingSeconds: newRemaining <= 0 ? newRemaining : newRemaining,
              isRunning: newRemaining > 0,
            );
          }
        }
      }

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
        _records.sort((a, b) => b.startTime.compareTo(a.startTime));
      }
    } catch (e) {
      debugPrint('加载记录失败: $e');
    }
  }

  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recordsKey, json.encode(_records.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('保存记录失败: $e');
    }
  }

  Future<void> _saveClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(_clocks.map((e) => e.toJson()).toList()));
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
        remainingSeconds: clock.isRunning ? clock.remainingSeconds : (durationSeconds ?? clock.remainingSeconds),
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

      if (clock.isRunning) return;

      // 查找是否有该时钟的未完成记录
      final existingIndex = _records.indexWhere(
        (r) => r.clockId == id && r.endTime == null
      );

      if (existingIndex != -1) {
        // 已有记录，恢复
        _records[existingIndex] = _records[existingIndex].copyWith(
          lastStartTime: now,
        );
      } else {
        // 新建记录
        final record = LabClockRecord(
          id: const Uuid().v4(),
          clockId: clock.id,
          clockTitle: clock.title,
          startTime: now,
          durationSeconds: clock.durationSeconds ?? 0,
          lastStartTime: now,
        );
        _records.insert(0, record);
      }

      _clocks[index] = clock.copyWith(
        isRunning: true,
        remainingSeconds: clock.durationSeconds ?? 0,
        startTime: now,
      );

      await _saveRecords();
      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> pauseCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      if (!clock.isRunning) return;

      // 暂停时钟
      _clocks[index] = clock.copyWith(isRunning: false);

      // 更新记录的实际时间
      final recordIndex = _records.indexWhere(
        (r) => r.clockId == id && r.endTime == null
      );

      if (recordIndex != -1) {
        final record = _records[recordIndex];
        final now = DateTime.now();
        final consumed = now.difference(record.lastStartTime!).inSeconds;

        _records[recordIndex] = record.copyWith(
          accumulatedSeconds: (record.accumulatedSeconds ?? 0) + consumed,
          lastStartTime: null,
        );
      }

      await _saveRecords();
      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> resetCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      final now = DateTime.now();

      // 先计算最后一次运行时间
      final recordIndex = _records.indexWhere(
        (r) => r.clockId == id && r.endTime == null
      );

      if (recordIndex != -1) {
        final record = _records[recordIndex];
        int totalSeconds = record.accumulatedSeconds ?? 0;

        // 如果正在运行，加上最后一次运行时间
        if (clock.isRunning && record.lastStartTime != null) {
          totalSeconds += now.difference(record.lastStartTime!).inSeconds;
        }

        _records[recordIndex] = record.copyWith(
          accumulatedSeconds: totalSeconds,
          endTime: now,
          completed: true,
          lastStartTime: null,
        );
      }

      // 重置时钟
      _clocks[index] = clock.copyWith(
        isRunning: false,
        remainingSeconds: clock.durationSeconds ?? 0,
      );

      await _saveRecords();
      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> updateTime(String id, int newDurationSeconds) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];
      _clocks[index] = clock.copyWith(
        durationSeconds: newDurationSeconds,
        remainingSeconds: clock.isRunning ? clock.remainingSeconds : newDurationSeconds,
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
