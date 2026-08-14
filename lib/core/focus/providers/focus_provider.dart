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

  int _sumMinutesOn(DateTime date) => _sessions
      .where((s) =>
          s.startTime.year == date.year &&
          s.startTime.month == date.month &&
          s.startTime.day == date.day)
      .fold<int>(0, (sum, s) => sum + s.durationMinutes);

  Future<void> clearAll() async {
    _sessions = [];
    await _saveData();
    notifyListeners();
  }
}
