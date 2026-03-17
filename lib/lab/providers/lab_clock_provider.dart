import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/lab_clock.dart';
import '../models/lab_clock_record.dart';

/// 极简时钟Provider - 数据驱动
/// 核心：只用一个数据源，每次操作直接写入最终状态
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
      bool changed = false;
      for (int i = 0; i < _clocks.length; i++) {
        if (_clocks[i].isRunning) {
          _clocks[i] = _clocks[i].copyWith(
            remainingSeconds: _clocks[i].remainingSeconds - 1
          );
          changed = true;
        }
      }
      if (changed) {
        _saveClocks();
        notifyListeners();
      }
    });
  }

  Future<void> loadClocks() async {
    final prefs = await SharedPreferences.getInstance();
    final clocksJson = prefs.getString(_storageKey);
    if (clocksJson != null) {
      final List<dynamic> list = json.decode(clocksJson);
      _clocks = list.map((e) => LabClock.fromJson(e)).toList();

      // 恢复运行状态
      final now = DateTime.now();
      for (int i = 0; i < _clocks.length; i++) {
        final c = _clocks[i];
        if (c.isRunning && c.startTime != null) {
          final elapsed = now.difference(c.startTime!).inSeconds;
          _clocks[i] = c.copyWith(remainingSeconds: (c.durationSeconds ?? 0) - elapsed);
        }
      }
    }

    await loadRecords();
    notifyListeners();
  }

  Future<void> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString(_recordsKey);
    if (recordsJson != null) {
      final List<dynamic> list = json.decode(recordsJson);
      _records = list.map((e) => LabClockRecord.fromJson(e)).toList();
      _records.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
  }

  Future<void> _saveClocks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, json.encode(_clocks.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, json.encode(_records.map((e) => e.toJson()).toList()));
  }

  /// 创建时钟
  Future<LabClock> createClock({
    String title = '新时钟',
    String description = '',
    int? durationSeconds,
    String? color,
  }) async {
    final clock = LabClock(
      id: const Uuid().v4(),
      title: title,
      description: description,
      createdAt: DateTime.now(),
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
    int? durationSeconds,
    String? color,
  }) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    _clocks[i] = c.copyWith(
      title: title ?? c.title,
      description: description ?? c.description,
      durationSeconds: durationSeconds ?? c.durationSeconds,
      remainingSeconds: c.isRunning ? c.remainingSeconds : (durationSeconds ?? c.remainingSeconds),
      color: color ?? c.color,
    );
    await _saveClocks();
    notifyListeners();
  }

  /// 启动
  Future<void> startCountdown(String id) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    if (c.isRunning) return;

    final now = DateTime.now();

    // 查找或创建记录
    int recordIdx = _records.indexWhere((r) => r.clockId == id && r.endTime == null);

    if (recordIdx == -1) {
      // 新建记录 - 记录当前开始时的remainingSeconds
      final record = LabClockRecord(
        id: const Uuid().v4(),
        clockId: c.id,
        clockTitle: c.title,
        startTime: now,
        durationSeconds: c.durationSeconds ?? 0,
        startRemaining: c.remainingSeconds,  // 启动时的剩余时间
      );
      _records.insert(0, record);
      recordIdx = 0;
    }

    // 更新时钟状态
    _clocks[i] = c.copyWith(
      isRunning: true,
      startTime: now,
    );

    await _saveRecords();
    await _saveClocks();
    notifyListeners();
  }

  /// 暂停 - 计算并保存实际消耗时间
  Future<void> pauseCountdown(String id) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    if (!c.isRunning) return;

    // 更新时钟状态
    _clocks[i] = c.copyWith(isRunning: false);

    // 计算本次消耗时间并保存
    int recordIdx = _records.indexWhere((r) => r.clockId == id && r.endTime == null);
    if (recordIdx != -1) {
      final record = _records[recordIdx];
      final consumed = (record.startRemaining ?? c.durationSeconds ?? 0) - c.remainingSeconds;
      _records[recordIdx] = record.copyWith(
        accumulatedSeconds: (record.accumulatedSeconds ?? 0) + consumed,
        startRemaining: null,  // 暂停后清除
      );
    }

    await _saveRecords();
    await _saveClocks();
    notifyListeners();
  }

  /// 重置
  Future<void> resetCountdown(String id) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    final now = DateTime.now();

    // 如果正在运行，先计算最后一次消耗
    if (c.isRunning) {
      int recordIdx = _records.indexWhere((r) => r.clockId == id && r.endTime == null);
      if (recordIdx != -1) {
        final record = _records[recordIdx];
        final consumed = (record.startRemaining ?? c.durationSeconds ?? 0) - c.remainingSeconds;
        _records[recordIdx] = record.copyWith(
          accumulatedSeconds: (record.accumulatedSeconds ?? 0) + consumed,
          endTime: now,
          completed: true,
          startRemaining: null,
        );
      }
    }

    // 重置时钟
    _clocks[i] = c.copyWith(
      isRunning: false,
      remainingSeconds: c.durationSeconds ?? 0,
    );

    await _saveRecords();
    await _saveClocks();
    notifyListeners();
  }

  /// 更新时长
  Future<void> updateTime(String id, int newDuration) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    _clocks[i] = c.copyWith(
      durationSeconds: newDuration,
      remainingSeconds: c.isRunning ? c.remainingSeconds : newDuration,
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

  /// 获取记录实时运行时间
  int getRecordLiveDuration(LabClockRecord record) {
    // 已完成：直接返回
    if (record.completed || record.endTime != null) {
      return record.accumulatedSeconds ?? 0;
    }

    // 进行中：加上当前运行时间
    final clock = getClockById(record.clockId);
    if (clock != null && clock.isRunning && record.startRemaining != null) {
      final consumed = record.startRemaining! - clock.remainingSeconds;
      return (record.accumulatedSeconds ?? 0) + consumed;
    }

    return record.accumulatedSeconds ?? 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
