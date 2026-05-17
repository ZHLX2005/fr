import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../native/home_widget/calendar_widget_data.dart';
import '../../native/home_widget/calendar_widget_service.dart';
import '../models/lab_calendar_event.dart';

/// 日历待办 Provider
///
/// - 增删改 events 后立即写 SharedPreferences 并同步到桌面 widget
/// - 视图月可切换（影响 widget 显示哪个月）；默认跟随今日
class LabCalendarProvider with ChangeNotifier {
  static const _storageKey = 'lab_calendar_events';
  static const _viewYearKey = 'lab_calendar_view_year';
  static const _viewMonthKey = 'lab_calendar_view_month';

  List<LabCalendarEvent> _events = [];
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;
  Timer? _midnightTimer;

  List<LabCalendarEvent> get events => List.unmodifiable(_events);
  int get viewYear => _viewYear;
  int get viewMonth => _viewMonth;

  LabCalendarProvider() {
    _loadAll();
    _scheduleMidnightRefresh();
  }

  /// 视图切月（month: 1-12，自动跨年）
  Future<void> setView(int year, int month) async {
    int y = year, m = month;
    while (m <= 0) {
      m += 12;
      y--;
    }
    while (m > 12) {
      m -= 12;
      y++;
    }
    if (y == _viewYear && m == _viewMonth) return;
    _viewYear = y;
    _viewMonth = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_viewYearKey, y);
    await prefs.setInt(_viewMonthKey, m);
    _syncToWidget();
    notifyListeners();
  }

  /// 切到上/下月
  Future<void> prevMonth() => setView(_viewYear, _viewMonth - 1);
  Future<void> nextMonth() => setView(_viewYear, _viewMonth + 1);

  /// 跳回今天
  Future<void> jumpToday() {
    final now = DateTime.now();
    return setView(now.year, now.month);
  }

  /// 取某天的事件（按创建顺序）
  List<LabCalendarEvent> eventsOf(int year, int month, int day) {
    final list = _events
        .where((e) => e.year == year && e.month == month && e.day == day)
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// 新增事件
  Future<LabCalendarEvent> addEvent({
    required int year,
    required int month,
    required int day,
    required String title,
    required String color,
    String? description,
  }) async {
    final e = LabCalendarEvent(
      id: const Uuid().v4(),
      year: year,
      month: month,
      day: day,
      title: title,
      color: color,
      description: description,
      createdAt: DateTime.now(),
    );
    _events.add(e);
    await _persist();
    _syncToWidget();
    notifyListeners();
    return e;
  }

  /// 更新
  Future<void> updateEvent({
    required String id,
    String? title,
    String? color,
    String? description,
    int? year,
    int? month,
    int? day,
  }) async {
    final i = _events.indexWhere((e) => e.id == id);
    if (i == -1) return;
    _events[i] = _events[i].copyWith(
      title: title,
      color: color,
      description: description,
      year: year,
      month: month,
      day: day,
    );
    await _persist();
    _syncToWidget();
    notifyListeners();
  }

  /// 删除
  Future<void> deleteEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
    await _persist();
    _syncToWidget();
    notifyListeners();
  }

  /// 清空某天
  Future<void> clearDay(int year, int month, int day) async {
    _events.removeWhere(
      (e) => e.year == year && e.month == month && e.day == day,
    );
    await _persist();
    _syncToWidget();
    notifyListeners();
  }

  // ── 内部 ─────────────────────────────────────────────

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        _events = list
            .map((e) => LabCalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (err) {
        debugPrint('[LabCalendarProvider] load failed: $err');
        _events = [];
      }
    }
    _viewYear = prefs.getInt(_viewYearKey) ?? DateTime.now().year;
    _viewMonth = prefs.getInt(_viewMonthKey) ?? DateTime.now().month;
    _syncToWidget();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      json.encode(_events.map((e) => e.toJson()).toList()),
    );
  }

  void _syncToWidget() {
    final data = CalendarWidgetData.fromEvents(
      year: _viewYear,
      month: _viewMonth,
      events: _events,
    );
    CalendarWidgetService.updateCalendarWidget(data);
  }

  /// 跨日时 widget 需要换"今日高亮"位置，简单每分钟检测一次（仅在午夜附近会触发实际重绘）
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    int lastDay = DateTime.now().day;
    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = DateTime.now().day;
      if (today != lastDay) {
        lastDay = today;
        _syncToWidget();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }
}
