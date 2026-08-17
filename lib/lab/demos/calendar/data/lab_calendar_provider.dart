import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../native/calendar/calendar_service.dart';
import '../../../../native/home_widget/calendar_widget_data.dart';
import '../../../../native/home_widget/calendar_widget_service.dart';
import '../domain/age_calculator.dart';
import '../../../../core/storage/hive/calendar_repository.dart';
import '../domain/event.dart';
import '../domain/recurrence.dart';
import '../lunar_adapter.dart';
import 'event_repository.dart';

class LabCalendarProvider with ChangeNotifier {
  final EventRepository _repo = EventRepository();
  final _lunar = LunarAdapter();
  final _uuid = const Uuid();
  Timer? _midnightTimer;

  List<Event> _events = [];
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;
  bool _ready = false;

  List<Event> get events => List.unmodifiable(_events);
  int get viewYear => _viewYear;
  int get viewMonth => _viewMonth;

  /// 是否正显示当前月（用于头部"今天"按钮的可见性判定）
  bool get isOnCurrentMonth {
    final n = DateTime.now();
    return _viewYear == n.year && _viewMonth == n.month;
  }

  /// 数据是否已加载完成（Hive init + 全量加载）。未完成时视图渲染 loading 占位。
  bool get ready => _ready;

  LabCalendarProvider() {
    _init();
  }

  Future<void> _init() async {
    await CalendarRepository.instance.init();
    _loadAll();
    _scheduleMidnightRefresh();
    _ready = true;
    notifyListeners();
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
    final box = CalendarRepository.instance.viewState;
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

  /// 某公历日的所有事件（正确处理农历：把单元格日期反查成农历再比对 lunar 事件）
  ///
  /// 之前 eventsOf 直接 e.month==month 匹配，对 lunar 事件（存农历月日）失效。
  /// 现在：solar 事件按公历月日匹配；lunar 事件把单元格日期 fromSolar 成农历
  /// 后比对农历月日 + isLeap——自动处理年份对齐（农历年跨公历年）。
  List<Event> eventsOnDate(DateTime date) {
    final lunar = _lunar.fromSolar(date);
    return _events.where((e) {
      if (e.system == CalendarSystem.solar) {
        return e.month == date.month && e.day == date.day;
      }
      return e.month == lunar.month &&
          e.day == lunar.day &&
          e.isLeap == lunar.isLeap;
    }).toList();
  }

  /// 事件在某公历年的发生日（用于年度报表按公历月分组）。
  /// lunar 事件：尝试 lunarYear∈{solarYear-1, solarYear}，取落在 solarYear 的那个。
  /// 找不到（如闰月该年不存在）返回 null。
  DateTime? solarOccurrenceInYear(Event e, int solarYear) {
    if (e.system == CalendarSystem.solar) {
      return DateTime(solarYear, e.month, e.day);
    }
    for (final ly in [solarYear - 1, solarYear]) {
      try {
        final s = _lunar.toSolar(ly, e.month, e.day, isLeap: e.isLeap);
        if (s.year == solarYear) {
          return DateTime(s.year, s.month, s.day);
        }
      } catch (_) {
        // 该农历年无此月日（如闰月），跳过
      }
    }
    return null;
  }

  Future<Event> add({
    required EventType type,
    required String title,
    required CalendarSystem system,
    required int month,
    required int day,
    required Recurrence recurrence,
    required ColorTag colorTag,
    int? year,
    bool isLeap = false,
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
      // year/month/day 是 system 历法下的值；year 缺省用今年（非 birthday 场景）
      year: year ?? DateTime.now().year,
      month: month,
      day: day,
      isLeap: isLeap,
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
    // 用事件在今年的公历发生日同步到系统日历（lunar 事件要先 resolve 到公历）
    final occurrence = solarOccurrenceInYear(event, DateTime.now().year) ??
        DateTime(event.year, event.month, event.day);
    final systemId = await CalendarService.insertEvent(
      title: event.title,
      description: event.note ?? '',
      year: occurrence.year,
      month: occurrence.month,
      day: occurrence.day,
    );
    if (systemId == null) return false;
    final updated = event.copyWith(systemCalendarEventId: systemId);
    _events[i] = updated;
    await _repo.update(updated);
    notifyListeners();
    return true;
  }

  /// 年龄计算（仅 birthday 类型）
  ///
  /// 公历生日：直接 DateTime(year, month, day)。
  /// 农历生日：year/month/day 是农历值，必须先用 lunarAnchorYear 换算成出生公历日
  /// （否则按农历月日当公历算会错）。闰月用 isLeap 标识。
  int? ageOfBirthdayPerson(Event birthdayEvent, DateTime today) {
    if (birthdayEvent.type != EventType.birthday) return null;
    DateTime dob;
    if (birthdayEvent.system == CalendarSystem.solar) {
      dob = DateTime(birthdayEvent.year, birthdayEvent.month, birthdayEvent.day);
    } else {
      final anchor = birthdayEvent.lunarAnchorYear ?? birthdayEvent.year;
      final s = LunarAdapter().toSolar(
        anchor,
        birthdayEvent.month,
        birthdayEvent.day,
        isLeap: birthdayEvent.isLeap,
      );
      dob = DateTime(s.year, s.month, s.day);
    }
    return AgeCalculator.calculate(dob, today);
  }

  Future<void> _loadAll() async {
    _events = _repo.load();
    final box = CalendarRepository.instance.viewState;
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
      lunar: _lunar,
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