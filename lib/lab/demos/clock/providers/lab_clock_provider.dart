import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../native/home_widget/clock_widget_data.dart';
import '../../../../native/home_widget/clock_widget_service.dart';
import '../models/lab_clock.dart';
import '../models/lab_clock_record.dart';
import 'beat_coordinator.dart';

/// 极简时钟Provider
class LabClockProvider with ChangeNotifier, WidgetsBindingObserver {
  List<LabClock> _clocks = [];
  List<LabClockRecord> _records = [];
  static const String _storageKey = 'lab_clocks_v2';
  static const String _recordsKey = 'lab_clock_records_v2';
  Timer? _timer;
  final Set<String> _silencedClocks = {};

  /// Clocks whose beat was stolen by another provider. UI greys out the beat dot.
  bool isClockSilenced(String clockId) => _silencedClocks.contains(clockId);

  List<LabClock> get clocks => _clocks;
  List<LabClockRecord> get records => _records;

  LabClockProvider() {
    _startTimer();
    WidgetsBinding.instance.addObserver(this);
    // 启动即加载数据并同步到桌面小组件
    // 之前要等 ClockDemo 页打开才 loadClocks，导致冷启动时 widget 看到的是空状态
    loadClocks();
    // 当被 track 抢占时，把对应 clock 标记为 silenced
    BeatCoordinator.registerBeatenOutCallback((id) {
      if (id.startsWith('clock:')) {
        _silencedClocks.add(id.substring('clock:'.length));
        notifyListeners();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 应用恢复时重新计算所有运行中的时钟
      _recalculateRunningClocks();
      // 无论是否变化都强制同步一次：widget 可能已被系统 30 分钟周期拉新过
      _syncToWidget();
    }
  }

  /// 重新计算运行中时钟的剩余时间（基于startTime）
  void _recalculateRunningClocks() {
    bool changed = false;
    for (int i = 0; i < _clocks.length; i++) {
      final clock = _clocks[i];
      if (clock.isRunning && clock.startTime != null) {
        // 使用startRemainingSeconds（如果有），否则兼容旧数据用durationSeconds
        final baseSeconds =
            clock.startRemainingSeconds ??
            clock.durationSeconds ??
            clock.remainingSeconds;
        final elapsed = DateTime.now().difference(clock.startTime!).inSeconds;
        final newRemaining = baseSeconds - elapsed;

        if (newRemaining != clock.remainingSeconds) {
          _clocks[i] = clock.copyWith(remainingSeconds: newRemaining);
          changed = true;
        }
      }
    }
    if (changed) {
      _saveClocks();
      notifyListeners();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      bool changed = false;
      for (int i = 0; i < _clocks.length; i++) {
        final clock = _clocks[i];
        if (clock.isRunning && clock.startTime != null) {
          // 使用startRemainingSeconds（如果有），否则兼容旧数据用durationSeconds
          final baseSeconds =
              clock.startRemainingSeconds ??
              clock.durationSeconds ??
              clock.remainingSeconds;
          final elapsed = DateTime.now().difference(clock.startTime!).inSeconds;
          final newRemaining = baseSeconds - elapsed;

          if (newRemaining != clock.remainingSeconds) {
            _clocks[i] = clock.copyWith(remainingSeconds: newRemaining);
            changed = true;
          }
        }
      }
      if (changed) {
        _saveClocks();
        _syncToWidget(); // 同步到桌面小组件
        notifyListeners();
      }
    });
  }

  // 震动与系统提示音已移除 — 倒计时结束由 metronome tick 提示（Oboe 单例）

  /// 同步第一个时钟数据到桌面小组件
  void _syncToWidget() {
    if (_clocks.isEmpty) {
      ClockWidgetService.clearClockWidget();
      return;
    }

    // 获取第一个时钟
    final clock = _clocks.first;
    final widgetData = ClockWidgetData.fromClock(
      title: clock.title,
      remainingSeconds: clock.remainingSeconds,
      durationSeconds: clock.durationSeconds ?? 0,
      isRunning: clock.isRunning,
      color: clock.color ?? '#2196F3',
      // 把 startTime / startRemainingSeconds 透传给 widget，
      // 让原生侧能基于 startTime 实时算 remaining，避免 Flutter 死掉后时间冻结
      startTime: clock.startTime,
      startRemainingSeconds: clock.startRemainingSeconds,
    );

    ClockWidgetService.updateClockWidget(widgetData);
  }

  Future<void> loadClocks() async {
    final prefs = await SharedPreferences.getInstance();
    final clocksJson = prefs.getString(_storageKey);

    // v1 -> v2 one-time migration. v1 used keys 'lab_clocks' / 'lab_clock_records';
    // their LabClock JSON lacked bpm / beatPattern. If v1 data exists, parse it
    // defensively, drop it if parsing fails, and let v2 start fresh.
    if (clocksJson == null) {
      final v1Json = prefs.getString('lab_clocks');
      if (v1Json != null) {
        // Old data: drop it. User explicitly chose 'no migration'.
        await prefs.remove('lab_clocks');
        await prefs.remove('lab_clock_records');
      }
    }

    if (clocksJson != null) {
      try {
        final List<dynamic> list = json.decode(clocksJson);
        _clocks = list.map((e) => LabClock.fromJson(e)).toList();
      } catch (_) {
        // Corrupt v2 data — wipe it so the user can add clocks again.
        await prefs.remove(_storageKey);
        _clocks = [];
      }
    }

    // Defensive: any clock with isRunning=true but startTime=null (legacy data)
    // is treated as paused so the Timer won't try to recalculate against null.
    _clocks = _clocks.map((c) {
      if (c.isRunning && c.startTime == null) {
        return c.copyWith(isRunning: false);
      }
      return c;
    }).toList();

    await loadRecords();
    // 加载完做一次"基于 startTime 重算"——
    // 如果用户在 app 死掉的时候有 running 的钟，重新打开后 remaining 已经过期了
    _recalculateRunningClocks();
    _syncToWidget();
    notifyListeners();
  }

  Future<void> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString(_recordsKey);
    if (recordsJson != null) {
      try {
        final List<dynamic> list = json.decode(recordsJson);
        _records = list.map((e) => LabClockRecord.fromJson(e)).toList();
        _records.sort((a, b) => b.startTime.compareTo(a.startTime));
      } catch (_) {
        await prefs.remove(_recordsKey);
        _records = [];
      }
    }
  }

  Future<void> _saveClocks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      json.encode(_clocks.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recordsKey,
      json.encode(_records.map((e) => e.toJson()).toList()),
    );
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
    _syncToWidget(); // 同步到桌面小组件
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
      remainingSeconds: c.isRunning
          ? c.remainingSeconds
          : (durationSeconds ?? c.remainingSeconds),
      color: color ?? c.color,
    );
    await _saveClocks();
    _syncToWidget(); // 同步到桌面小组件
    notifyListeners();
  }

  /// 启动
  Future<void> startCountdown(String id) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    if (c.isRunning) return;

    final now = DateTime.now();

    // 查找或创建记录（只创建，不累加）
    int recordIdx = _records.indexWhere(
      (r) => r.clockId == id && r.endTime == null,
    );

    if (recordIdx == -1) {
      final record = LabClockRecord(
        id: const Uuid().v4(),
        clockId: c.id,
        clockTitle: c.title,
        startTime: now,
        durationSeconds: c.durationSeconds ?? 0,
      );
      _records.insert(0, record);
    }

    // 保存启动时刻的剩余时间和开始时间，用于后续计算
    _clocks[i] = c.copyWith(
      isRunning: true,
      startTime: now,
      startRemainingSeconds: c.remainingSeconds,
    );
    final c2 = _clocks[i];

    await _saveRecords();
    await _saveClocks();
    _syncToWidget(); // 同步到桌面小组件
    if (c2.bpm != null) {
      BeatCoordinator.requestOwnership(
        providerId: 'clock:$id',
        bpm: c2.bpm,
        beatPattern: c2.beatPattern,
      );
    }
    notifyListeners();
  }

  /// 暂停
  Future<void> pauseCountdown(String id) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    // Clear startTime/startRemainingSeconds so a future app resume doesn't
    // recalculate against a stale wall-clock and produce a negative remaining.
    _clocks[i] = _clocks[i].copyWith(
      isRunning: false,
      startTime: null,
      startRemainingSeconds: null,
    );
    await _saveClocks();
    _syncToWidget(); // 同步到桌面小组件
    BeatCoordinator.releaseOwnership('clock:$id');
    notifyListeners();
  }

  /// 重置 - 直接记录当前显示的时间作为实际时间
  Future<void> resetCountdown(String id) async {
    final i = _clocks.indexWhere((c) => c.id == id);
    if (i == -1) return;

    final c = _clocks[i];
    final now = DateTime.now();

    // 计算已消耗时间 = 总时长 - 当前剩余
    final consumed = (c.durationSeconds ?? 0) - c.remainingSeconds;

    // 查找或更新记录
    int recordIdx = _records.indexWhere(
      (r) => r.clockId == id && r.endTime == null,
    );

    if (recordIdx != -1) {
      _records[recordIdx] = _records[recordIdx].copyWith(
        accumulatedSeconds: consumed,
        endTime: now,
        completed: true,
      );
    }

    // 重置时钟 — clear startTime/startRemainingSeconds so resume doesn't
    // recalculate against a stale wall-clock.
    _clocks[i] = c.copyWith(
      isRunning: false,
      remainingSeconds: c.durationSeconds ?? 0,
      startTime: null,
      startRemainingSeconds: null,
    );

    await _saveRecords();
    await _saveClocks();
    _syncToWidget(); // 同步到桌面小组件
    BeatCoordinator.releaseOwnership('clock:$id');
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
    _syncToWidget(); // 同步到桌面小组件
    notifyListeners();
  }

  /// 删除时钟
  Future<void> deleteClock(String id) async {
    _clocks.removeWhere((c) => c.id == id);
    await _saveClocks();
    _syncToWidget(); // 同步到桌面小组件
    notifyListeners();
  }

  /// 删除记录
  /// 更新记录的自定义名称
  Future<void> updateRecordTitle(String id, String customTitle) async {
    final i = _records.indexWhere((r) => r.id == id);
    if (i == -1) return;

    _records[i] = _records[i].copyWith(customTitle: customTitle);
    await _saveRecords();
    notifyListeners();
  }

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

  /// Configure the BPM and pattern for a clock. Pass nulls to clear.
  Future<void> setBeat(String clockId, {int? bpm, String? beatPattern}) async {
    final i = _clocks.indexWhere((c) => c.id == clockId);
    if (i == -1) return;
    _clocks[i] = _clocks[i].copyWith(bpm: bpm, beatPattern: beatPattern);
    await _saveClocks();
    _syncToWidget();
    notifyListeners();
  }

  /// Remove beat config from a clock and stop its metronome if running.
  Future<void> clearBeat(String clockId) async {
    final i = _clocks.indexWhere((c) => c.id == clockId);
    if (i == -1) return;
    final wasRunning = _clocks[i].isRunning;
    await setBeat(clockId, bpm: null, beatPattern: null);
    if (wasRunning) {
      BeatCoordinator.releaseOwnership('clock:$clockId');
    }
  }

  /// The id of the clock currently driving the metronome, or null.
  String? get activeBeatClockId {
    final owner = BeatCoordinator.ownerId;
    if (owner == null) return null;
    if (!owner.startsWith('clock:')) return null;
    return owner.substring('clock:'.length);
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
    // 已完成：直接返回保存的值
    if (record.completed) {
      return record.accumulatedSeconds ?? 0;
    }
    // 获取关联的时钟
    final clock = getClockById(record.clockId);
    if (clock != null) {
      // 时钟存在：计算当前已消耗时间（无论是否暂停）
      return (record.durationSeconds) - clock.remainingSeconds;
    }
    // 时钟不存在且未完成：返回0
    return 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
