import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/lab_clock.dart';
import '../models/lab_clock_record.dart';

/// 简单数据驱动的时钟Provider
/// 核心原则：所有时间计算统一在provider内完成，UI只负责显示
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
      // 每秒更新，触发UI刷新
      notifyListeners();
    });
  }

  Future<void> loadClocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clocksJson = prefs.getString(_storageKey);
      if (clocksJson != null) {
        final List<dynamic> clocksList = json.decode(clocksJson);
        _clocks = clocksList.map((e) => LabClock.fromJson(e)).toList();

        // 恢复运行时状态
        final now = DateTime.now();
        for (int i = 0; i < _clocks.length; i++) {
          final clock = _clocks[i];
          if (clock.isRunning && clock.startTime != null) {
            final elapsed = now.difference(clock.startTime!).inSeconds;
            final newRemaining = (clock.durationSeconds ?? 0) - elapsed;
            _clocks[i] = clock.copyWith(remainingSeconds: newRemaining);
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

  /// 创建时钟
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

  /// 更新时钟
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

  /// 启动倒计时
  Future<void> startCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final clock = _clocks[index];
    if (clock.isRunning) return;

    final now = DateTime.now();

    // 查找是否有该时钟的未结束记录
    final recordIndex = _records.indexWhere(
      (r) => r.clockId == id && r.endTime == null
    );

    if (recordIndex != -1) {
      // 恢复记录
      final record = _records[recordIndex];
      _records[recordIndex] = record.copyWith(lastStartTime: now);
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

    // 启动时钟
    _clocks[index] = clock.copyWith(
      isRunning: true,
      remainingSeconds: clock.durationSeconds ?? 0,
      startTime: now,
    );

    await _saveRecords();
    await _saveClocks();
    notifyListeners();
  }

  /// 暂停倒计时 - 保存已运行时间
  Future<void> pauseCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final clock = _clocks[index];
    if (!clock.isRunning) return;

    final now = DateTime.now();

    // 查找记录并累加时间
    final recordIndex = _records.indexWhere(
      (r) => r.clockId == id && r.endTime == null
    );

    if (recordIndex != -1) {
      final record = _records[recordIndex];
      final consumed = now.difference(record.lastStartTime!).inSeconds;
      _records[recordIndex] = record.copyWith(
        accumulatedSeconds: (record.accumulatedSeconds ?? 0) + consumed,
        lastStartTime: null,
      );
    }

    // 暂停时钟
    _clocks[index] = clock.copyWith(isRunning: false);

    await _saveRecords();
    await _saveClocks();
    notifyListeners();
  }

  /// 重置倒计时 - 完成记录
  Future<void> resetCountdown(String id) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final clock = _clocks[index];
    final now = DateTime.now();

    // 查找并完成记录
    final recordIndex = _records.indexWhere(
      (r) => r.clockId == id && r.endTime == null
    );

    if (recordIndex != -1) {
      final record = _records[recordIndex];
      int total = record.accumulatedSeconds ?? 0;

      // 如果正在运行，加上最后一段时间
      if (clock.isRunning && record.lastStartTime != null) {
        total += now.difference(record.lastStartTime!).inSeconds;
      }

      _records[recordIndex] = record.copyWith(
        accumulatedSeconds: total,
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

  /// 更新时间
  Future<void> updateTime(String id, int newDurationSeconds) async {
    final index = _clocks.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final clock = _clocks[index];
    _clocks[index] = clock.copyWith(
      durationSeconds: newDurationSeconds,
      remainingSeconds: clock.isRunning ? clock.remainingSeconds : newDurationSeconds,
    );
    await _saveClocks();
    notifyListeners();
  }

  /// 删除时钟
  Future<void> deleteClock(String id) async {
    _clocks.removeWhere((c) => c.id == id);
    await _saveClocks();
    notifyListeners();
  }

  /// 删除记录
  Future<void> deleteRecord(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _saveRecords();
    notifyListeners();
  }

  /// 清空记录
  Future<void> clearRecords() async {
    _records.clear();
    await _saveRecords();
    notifyListeners();
  }

  /// 获取时钟
  LabClock? getClockById(String id) {
    try {
      return _clocks.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 获取记录的实时运行时间（用于UI显示）
  int getRecordLiveDuration(LabClockRecord record) {
    // 如果已完成，直接返回累计时间
    if (record.completed || record.endTime != null) {
      return record.accumulatedSeconds ?? 0;
    }

    // 如果正在进行，加上当前运行的时间
    if (record.lastStartTime != null) {
      final now = DateTime.now();
      final currentRun = now.difference(record.lastStartTime!).inSeconds;
      return (record.accumulatedSeconds ?? 0) + currentRun;
    }

    return record.accumulatedSeconds ?? 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
