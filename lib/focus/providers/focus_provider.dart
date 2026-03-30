import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/focus_subject.dart';
import '../models/focus_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'focus_timer_provider.dart';

/// 专注数据管理Provider
class FocusProvider extends ChangeNotifier {
  List<FocusSubject> _subjects = [];
  List<FocusSession> _sessions = [];
  bool _isLoading = true;

  // 计时器恢复相关
  static const String _timerSecondsKey = 'focus_timer_seconds';
  static const String _timerSubjectKey = 'focus_timer_subject';

  List<FocusSubject> get subjects => List.unmodifiable(_subjects);
  List<FocusSession> get sessions => List.unmodifiable(_sessions);
  bool get isLoading => _isLoading;

  /// 初始化
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    await _loadData();

    _isLoading = false;
    notifyListeners();
  }

  /// 恢复计时器状态（供外部调用）
  Future<void> restoreTimerState(FocusTimerProvider timerProvider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSeconds = prefs.getInt(_timerSecondsKey) ?? 0;
      final savedSubjectId = prefs.getString(_timerSubjectKey);

      if (savedSeconds > 0 && savedSubjectId != null) {
        // 找到对应的科目
        final subject = _subjects.firstWhere(
          (s) => s.id == savedSubjectId,
          orElse: () => _subjects.isNotEmpty ? _subjects.first : FocusSubject(
            id: 'default',
            name: '默认',
            color: const Color(0xFF9CAF88),
            icon: '📚',
          ),
        );
        timerProvider.restoreSubject(subject);
      }
    } catch (e) {
      debugPrint('恢复计时器科目失败: $e');
    }
  }

  /// 加载数据
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载科目
    final subjectsJson = prefs.getString('focus_subjects');
    if (subjectsJson != null && subjectsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(subjectsJson);
        _subjects = decoded.map((json) => FocusSubject.fromJson(json)).toList();
      } catch (e) {
        debugPrint('加载科目失败: $e');
        _subjects = List.from(FocusSubjectPresets.presets);
      }
    } else {
      _subjects = List.from(FocusSubjectPresets.presets);
    }

    // 加载会话记录
    final sessionsJson = prefs.getString('focus_sessions');
    if (sessionsJson != null && sessionsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(sessionsJson);
        _sessions = decoded.map((json) => FocusSession.fromJson(json)).toList();
      } catch (e) {
        debugPrint('加载会话失败: $e');
        _sessions = [];
      }
    }
  }

  /// 保存数据
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    // 保存科目
    final subjectsJson = json.encode(_subjects.map((s) => s.toJson()).toList());
    await prefs.setString('focus_subjects', subjectsJson);

    // 保存会话
    final sessionsJson = json.encode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString('focus_sessions', sessionsJson);
  }

  /// 添加科目
  Future<void> addSubject(FocusSubject subject) async {
    _subjects.add(subject);
    await _saveData();
    notifyListeners();
  }

  /// 更新科目
  Future<void> updateSubject(FocusSubject subject) async {
    final index = _subjects.indexWhere((s) => s.id == subject.id);
    if (index != -1) {
      _subjects[index] = subject;
      await _saveData();
      notifyListeners();
    }
  }

  /// 删除科目
  Future<void> deleteSubject(String id) async {
    _subjects.removeWhere((s) => s.id == id);
    await _saveData();
    notifyListeners();
  }

  /// 添加会话记录
  Future<void> addSession(FocusSession session) async {
    _sessions.add(session);

    // 更新对应科目的完成学时
    final subjectIndex = _subjects.indexWhere((s) => s.id == session.subjectId);
    if (subjectIndex != -1) {
      final subject = _subjects[subjectIndex];
      _subjects[subjectIndex] = subject.copyWith(
        completedMinutes: subject.completedMinutes + session.durationMinutes,
      );
    }

    await _saveData();
    notifyListeners();
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

  /// 获取本周总学时（分钟）
  int getWeekMinutes() {
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );

    return _sessions
        .where((session) => session.startTime.isAfter(weekStart) || session.startTime.isAtSameMomentAs(weekStart))
        .fold<int>(0, (sum, session) => sum + session.durationMinutes);
  }

  /// 获取科目总学时
  int getSubjectMinutes(String subjectId) {
    return _sessions
        .where((session) => session.subjectId == subjectId)
        .fold<int>(0, (sum, session) => sum + session.durationMinutes);
  }

  /// 获取热力图数据（最近7天）
  List<Map<String, dynamic>> getHeatmapData() {
    final data = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      final dayMinutes = _sessions
          .where((session) =>
              session.startTime.year == date.year &&
              session.startTime.month == date.month &&
              session.startTime.day == date.day)
          .fold<int>(0, (sum, session) => sum + session.durationMinutes);

      data.add({
        'date': date,
        'minutes': dayMinutes,
        'level': _getHeatmapLevel(dayMinutes),
      });
    }

    return data;
  }

  /// 获取热力图级别（0-4）
  int _getHeatmapLevel(int minutes) {
    if (minutes == 0) return 0;
    if (minutes < 30) return 1;
    if (minutes < 60) return 2;
    if (minutes < 120) return 3;
    return 4;
  }

  /// 清除所有数据
  Future<void> clearAll() async {
    _subjects = List.from(FocusSubjectPresets.presets);
    _sessions = [];
    await _saveData();
    notifyListeners();
  }
}
