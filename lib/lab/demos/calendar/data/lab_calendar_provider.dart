import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../native/calendar/calendar_service.dart';
import '../../../../native/home_widget/calendar_widget_data.dart';
import '../../../../native/home_widget/calendar_widget_service.dart';
import '../domain/age_calculator.dart';
import '../domain/event.dart';
import '../domain/recurrence.dart';
import 'calendar_hive.dart';
import 'event_repository.dart';

class LabCalendarProvider with ChangeNotifier {
  final EventRepository _repo = EventRepository();
  final _uuid = const Uuid();
  Timer? _midnightTimer;

  List<Event> _events = [];
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;

  List<Event> get events => List.unmodifiable(_events);
  int get viewYear => _viewYear;
  int get viewMonth => _viewMonth;

  LabCalendarProvider() {
    _init();
  }

  Future<void> _init() async {
    await CalendarHive.init();
    _loadAll();
    _scheduleMidnightRefresh();
  }

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
    final box = CalendarHive.viewState;
    await box.put('viewYear', y);
    await box.put('viewMonth', m);
    _syncToWidget();
    notifyListeners();
  }

  Future<void> prevMonth() => setView(_viewYear, _viewMonth - 1);
  Future<void> nextMonth() => setView(_viewYear, _viewMonth + 1);
  Future<void> jumpToday() {
    final n = DateTime.now();
    return setView(n.year, n.month);
  }

  /// 取某天的所有事件（按 month/day 匹配，不做农历推算）
  List<Event> eventsOf(int month, int day) =>
      _events.where((e) => e.month == month && e.day == day).toList();

  Future<Event> add({
    required EventType type,
    required String title,
    required CalendarSystem system,
    required int month,
    required int day,
    required Recurrence recurrence,
    required ColorTag colorTag,
    int? solarYearOffset,
    String? personId,
    String? note,
    int? lunarAnchorYear,
  }) async {
    final e = Event(
      id: _uuid.v4(),
      type: type,
      title: title,
      system: system,
      year: DateTime.now().year,
      month: month,
      day: day,
      recurrence: recurrence,
      colorTag: colorTag,
      solarYearOffset: solarYearOffset,
      personId: personId,
      note: note,
      lunarAnchorYear: lunarAnchorYear,
      createdAt: DateTime.now(),
    );
    _events.add(e);
    await _repo.add(e);
    _syncToWidget();
    notifyListeners();
    return e;
  }

  Future<void> update(Event e) async {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i == -1) return;
    _events[i] = e;
    await _repo.update(e);
    _syncToWidget();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final event = _events.firstWhere((e) => e.id == id);
    if (event.systemCalendarEventId != null) {
      await CalendarService.deleteEvent(event.systemCalendarEventId!);
    }
    _events.removeWhere((e) => e.id == id);
    await _repo.delete(id);
    _syncToWidget();
    notifyListeners();
  }

  /// 同步到系统日历（保留旧能力）
  Future<bool> syncToSystemCalendar(String id) async {
    final i = _events.indexWhere((e) => e.id == id);
    if (i == -1) return false;
    final event = _events[i];
    final hasPermission = await CalendarService.checkPermission();
    if (!hasPermission) {
      await CalendarService.requestPermission();
      if (!await CalendarService.checkPermission()) return false;
    }
    if (event.systemCalendarEventId != null) {
      await CalendarService.deleteEvent(event.systemCalendarEventId!);
    }
    final systemId = await CalendarService.insertEvent(
      title: event.title,
      description: event.note ?? '',
      year: event.year,
      month: event.month,
      day: event.day,
    );
    if (systemId == null) return false;
    final updated = event.copyWith(systemCalendarEventId: systemId);
    _events[i] = updated;
    await _repo.update(updated);
    notifyListeners();
    return true;
  }

  /// 年龄计算（仅 birthday 类型）
  int? ageOfBirthdayPerson(Event birthdayEvent, DateTime today) {
    if (birthdayEvent.type != EventType.birthday) return null;
    final dob = DateTime(birthdayEvent.year, birthdayEvent.month, birthdayEvent.day);
    return AgeCalculator.calculate(dob, today);
  }

  Future<void> _loadAll() async {
    _events = _repo.load();
    final box = CalendarHive.viewState;
    _viewYear = (box.get('viewYear') as int?) ?? DateTime.now().year;
    _viewMonth = (box.get('viewMonth') as int?) ?? DateTime.now().month;
    _syncToWidget();
    notifyListeners();
  }

  void _syncToWidget() {
    final data = CalendarWidgetData.fromEvents(
      year: _viewYear,
      month: _viewMonth,
      events: _events,
    );
    CalendarWidgetService.updateCalendarWidget(data);
  }

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