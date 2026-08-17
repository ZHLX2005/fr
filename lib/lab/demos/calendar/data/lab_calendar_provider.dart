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
import '../data/calendar_config.dart';
import 'event_repository.dart';

class LabCalendarProvider with ChangeNotifier {
  /// 当前活跃实例（由构造时设置，供非 Consumer 上下文访问如 ImportDialog / Settings）
  static LabCalendarProvider? current;

  final EventRepository _repo = EventRepository();
  final _lunar = LunarAdapter();
  final _uuid = const Uuid();
  Timer? _midnightTimer;

  List<Event> _events = [];
  List<CalendarGroup> _groups = const [
    CalendarGroup(id: CalendarGroup.defaultGroupId, name: '默认日历', createdAt: 0),
  ];
  String _activeGroupId = CalendarGroup.defaultGroupId;
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;
  bool _ready = false;

  /// 当前 group 的事件（按 groupId 过滤）
  List<Event> get events =>
      List.unmodifiable(_events.where((e) => e.groupId == _activeGroupId));

  /// 所有事件（不过滤；DSL 应用等内部用）
  List<Event> get allEvents => List.unmodifiable(_events);

  List<CalendarGroup> get groups => List.unmodifiable(_groups);
  String get activeGroupId => _activeGroupId;
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
    current = this;
    _init();
  }

  Future<void> _init() async {
    final repo = CalendarRepository.instance;
    await repo.init();
    _activeGroupId = await repo.getActiveGroupId();
    _groups = await repo.loadGroups();
    _loadAll();
    _scheduleMidnightRefresh();
    _ready = true;
    notifyListeners();
  }

  // ──── group 操作（仿 timetable 多空间）──────

  /// 切换激活 group
  Future<void> setActiveGroup(String groupId) async {
    if (_activeGroupId == groupId) return;
    _activeGroupId = groupId;
    await CalendarRepository.instance.setActiveGroup(groupId);
    _syncToWidget();
    notifyListeners();
  }

  /// 新建 group 并切换过去
  Future<void> createGroup(String name, {String? note}) async {
    final id = 'g_${DateTime.now().millisecondsSinceEpoch}';
    final g = CalendarGroup(
      id: id,
      name: name,
      note: note,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await CalendarRepository.instance.saveGroup(g);
    _groups = await CalendarRepository.instance.loadGroups();
    await setActiveGroup(id);
  }

  /// 重命名 group
  Future<void> renameGroup(String id, String name) async {
    final g = _groups.firstWhere(
      (x) => x.id == id,
      orElse: () => CalendarGroup(
        id: id,
        name: name,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await CalendarRepository.instance.saveGroup(g.copyWith(name: name));
    _groups = await CalendarRepository.instance.loadGroups();
    notifyListeners();
  }

  /// 删除 group（default 不可删；删除当前激活组自动回退 default）
  Future<void> deleteGroup(String id) async {
    if (id == CalendarGroup.defaultGroupId) return;
    await CalendarRepository.instance.deleteGroup(id);
    // 同时删除该 group 的事件
    _events.removeWhere((e) => e.groupId == id);
    await _saveAll();
    _groups = await CalendarRepository.instance.loadGroups();
    if (_activeGroupId == id) {
      _activeGroupId = CalendarGroup.defaultGroupId;
      await CalendarRepository.instance
          .setActiveGroup(CalendarGroup.defaultGroupId);
    }
    _syncToWidget();
    notifyListeners();
  }

  /// 批量写入事件（DSL 解析结果用）
  Future<int> importEvents(List<Event> events) async {
    final newOnes = events.map((e) {
      return e.copyWith(groupId: _activeGroupId);
    }).toList();
    _events.addAll(newOnes);
    await _saveAll();
    _syncToWidget();
    notifyListeners();
    return newOnes.length;
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
      groupId: _activeGroupId,
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
    final repo = CalendarRepository.instance;
    _events = repo.events.values.toList();
    final box = repo.viewState;
    _viewYear = (box.get('viewYear') as int?) ?? DateTime.now().year;
    _viewMonth = (box.get('viewMonth') as int?) ?? DateTime.now().month;
    _syncToWidget();
    notifyListeners();
  }

  /// 整批刷盘：clear box 后重写
  Future<void> _saveAll() async {
    final repo = CalendarRepository.instance;
    await repo.events.clear();
    for (final e in _events) {
      await repo.events.put(e.id, e);
    }
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