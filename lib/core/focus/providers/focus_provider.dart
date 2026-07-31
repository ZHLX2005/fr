import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/focus_session.dart';

/// 专注数据管理Provider（只管 sessions：学科已移除）。
class FocusProvider extends ChangeNotifier {
  List<FocusSession> _sessions = [];
  bool _isLoading = true;

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

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = prefs.getString('focus_sessions');
    if (sessionsJson != null && sessionsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(sessionsJson);
        _sessions = decoded.map((j) => FocusSession.fromJson(j)).toList();
      } catch (e) {
        debugPrint('加载会话失败: $e');
        _sessions = [];
      }
    }
    // legacy focus_subjects JSON 直接忽略
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson =
        json.encode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString('focus_sessions', sessionsJson);
  }

  /// 添加会话记录
  Future<void> addSession(FocusSession session) async {
    _sessions.add(session);
    await _saveData();
    notifyListeners();
  }

  /// 今日总学时（分钟）
  int getTodayMinutes() => _sumMinutesOn(DateTime.now());

  /// 本周总学时（分钟）
  int getWeekMinutes() {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return _sessions
        .where((s) => !s.startTime.isBefore(weekStart))
        .fold<int>(0, (sum, s) => sum + s.durationMinutes);
  }

  /// 最近 7 天热力图
  List<Map<String, dynamic>> getHeatmapData() {
    final data = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      data.add({
        'date': date,
        'minutes': _sumMinutesOn(date),
        'level': _heatmapLevel(_sumMinutesOn(date)),
      });
    }
    return data;
  }

  int _sumMinutesOn(DateTime date) => _sessions
      .where((s) =>
          s.startTime.year == date.year &&
          s.startTime.month == date.month &&
          s.startTime.day == date.day)
      .fold<int>(0, (sum, s) => sum + s.durationMinutes);

  int _heatmapLevel(int minutes) {
    if (minutes == 0) return 0;
    if (minutes < 30) return 1;
    if (minutes < 60) return 2;
    if (minutes < 120) return 3;
    return 4;
  }

  Future<void> clearAll() async {
    _sessions = [];
    await _saveData();
    notifyListeners();
  }
}
