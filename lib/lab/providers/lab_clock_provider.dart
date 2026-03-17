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

  /// 完成记录
  Future<void> _completeRecord(String clockId, {bool completed = true}) async {
    if (_currentRecordId != null) {
      final index = _records.indexWhere((r) => r.id == _currentRecordId);
      if (index != -1) {
        final record = _records[index];

        // 结束当前会话（如果有进行中的会话）
        var updatedRecord = record.endCurrentSession();

        // 标记为完成
        updatedRecord = updatedRecord.copyWith(
          endTime: DateTime.now(),
          completed: completed,
        );

        _records[index] = updatedRecord;
        await _saveRecords();
      }
      _currentRecordId = null;
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

      // 确定新的剩余时间
      int newRemainingSeconds;
      if (durationSeconds != null && !clock.isRunning) {
        // 如果更新了时长且时钟未运行，更新剩余时间为新时长
        newRemainingSeconds = durationSeconds;
      } else if (durationSeconds != null && clock.isRunning) {
        // 如果时钟正在运行，保持当前剩余时间不变
        newRemainingSeconds = clock.remainingSeconds;
      } else {
        // 如果没有更新时长，保持原剩余时间
        newRemainingSeconds = clock.remainingSeconds;
      }

      _clocks[index] = clock.copyWith(
        title: title ?? clock.title,
        description: description ?? clock.description,
        targetTime: targetTime ?? clock.targetTime,
        durationSeconds: durationSeconds ?? clock.durationSeconds,
        remainingSeconds: newRemainingSeconds,
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
      LabClockRecord record;
      final existingRecordIndex = _records.indexWhere(
        (r) => r.clockId == id && r.endTime == null
      );

      if (existingRecordIndex != -1) {
        // 恢复现有记录
        record = _records[existingRecordIndex];
        _currentRecordId = record.id;

        // 创建新会话
        final newSession = ClockSession(
          id: const Uuid().v4(),
          startTime: now,
        );
        _records[existingRecordIndex] = record.addSession(newSession);
      } else {
        // 创建新记录
        final newSession = ClockSession(
          id: const Uuid().v4(),
          startTime: now,
        );
        record = LabClockRecord(
          id: const Uuid().v4(),
          clockId: clock.id,
          clockTitle: clock.title,
          startTime: now,
          durationSeconds: clock.durationSeconds ?? 0,
          sessions: [newSession],
        );
        _records.insert(0, record);
        _currentRecordId = record.id;
      }

      await _saveRecords();

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

      // 如果时钟不在运行，不做任何事
      if (!clock.isRunning) {
        return;
      }

      // 暂停时钟
      _clocks[index] = clock.copyWith(isRunning: false);

      // 结束当前记录中的当前会话
      if (_currentRecordId != null) {
        final recordIndex = _records.indexWhere((r) => r.id == _currentRecordId && r.clockId == id);
        if (recordIndex != -1) {
          _records[recordIndex] = _records[recordIndex].endCurrentSession();
          await _saveRecords();
        }
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
      await _completeRecord(id, completed: true);

      await _saveClocks();
      notifyListeners();
    }
  }

  Future<void> updateTime(String id, int newDurationSeconds) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index != -1) {
      final clock = _clocks[index];

      // 更新时钟时长
      // 如果时钟未运行，直接更新剩余时间为新时长
      // 如果时钟正在运行，保持当前的剩余时间（或可根据需求调整）
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
