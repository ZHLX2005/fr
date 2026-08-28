import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../native/calendar/calendar_service.dart';
import '../../../../native/home_widget/calendar_widget_data.dart';
import '../../../../native/home_widget/calendar_widget_service.dart';
import '../domain/age_calculator.dart';
import '../../../../core/storage/hive/calendar_repository.dart';
import '../domain/anchor.dart';
import '../domain/event.dart';
import '../domain/event_occurrence.dart';
import '../domain/period.dart';
import '../lunar_adapter.dart';
import '../data/calendar_config.dart';
import '../data/event_draft.dart';
import '../data/event_v1_migration.dart';
import '../data/lab_people_provider.dart';
import '../data/occurrence_engine.dart';
import '../service/dsl/dsl_exporter.dart';
import '../service/dsl/dsl_interpreter.dart';
import '../service/dsl/dsl_parser.dart';

/// DSL apply 报告。
class DslApplyReport {
  final int added;
  final int skipped;
  final List<Object> errors; // DslError but typed loose to avoid leak
  const DslApplyReport({
    required this.added,
    required this.skipped,
    required this.errors,
  });
}

class LabCalendarProvider with ChangeNotifier {
  static LabCalendarProvider? current;

  final _uuid = const Uuid();
  final _lunar = LunarAdapter();
  Timer? _midnightTimer;

  List<Event> _events = [];
  List<CalendarGroup> _groups = const [
    CalendarGroup(id: CalendarGroup.defaultGroupId, name: '默认日历', createdAt: 0),
  ];
  String _activeGroupId = CalendarGroup.defaultGroupId;
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;
  bool _ready = false;
  int _lastDroppedMigrationCount = 0;

  /// 当前 group 的事件（按 groupId 过滤）
  List<Event> get events =>
      List.unmodifiable(_events.where((e) => e.groupId == _activeGroupId));

  /// 所有事件（不过滤）
  List<Event> get allEvents => List.unmodifiable(_events);

  List<CalendarGroup> get groups => List.unmodifiable(_groups);
  String get activeGroupId => _activeGroupId;
  int get viewYear => _viewYear;
  int get viewMonth => _viewMonth;

  bool get isOnCurrentMonth {
    final n = DateTime.now();
    return _viewYear == n.year && _viewMonth == n.month;
  }

  bool get ready => _ready;

  /// 首次启动时迁移丢弃的记录条数（用户一次性 toast 用）。
  int get lastDroppedMigrationCount => _lastDroppedMigrationCount;

  LabCalendarProvider() {
    current = this;
    _init();
  }

  Future<void> _init() async {
    final repo = CalendarRepository.instance;
    try {
      await repo.init();

      // 升级时若 events box 因 frame header 不可读已被重置，直接当作空盒。
      if (repo.eventsBoxWasReset) {
        _lastDroppedMigrationCount = -1; // 哨兵：表示"已重置"
        _activeGroupId = await repo.getActiveGroupId();
        _groups = await repo.loadGroups();
        _loadAll();
        _scheduleMidnightRefresh();
        return;
      }

      // 一次性 v1→v2 迁移（仅在 Map-shaped 数据上工作）
      final raw = repo.events.values.toList();
      final mig = EventV1Migration.run(raw);
      _lastDroppedMigrationCount = mig.droppedIds.length;
      if (raw.isNotEmpty) {
        await repo.clearEvents();
        for (final d in mig.drafts) {
          await _addInternal(d);
        }
      }

      _activeGroupId = await repo.getActiveGroupId();
      _groups = await repo.loadGroups();
      _loadAll();
      _scheduleMidnightRefresh();
    } catch (e, st) {
      // 永不抛出 —— 否则 _ready 永远 false，UI 一直转圈。
      debugPrint('[LabCalendarProvider] _init failed: $e\n$st');
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  // ──── group 操作（仿 timetable 多空间）──────

  Future<void> setActiveGroup(String groupId) async {
    if (_activeGroupId == groupId) return;
    _activeGroupId = groupId;
    await CalendarRepository.instance.setActiveGroup(groupId);
    _syncToWidget();
    notifyListeners();
  }

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

  Future<void> deleteGroup(String id) async {
    if (id == CalendarGroup.defaultGroupId) return;
    await CalendarRepository.instance.deleteGroup(id);
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

  Future<void> clearActiveGroupItems() async {
    final activeId = _activeGroupId;
    _events.removeWhere((e) => e.groupId == activeId);
    await _saveAll();
    _syncToWidget();
    notifyListeners();
  }

  // ──── 视图 ────

  Future<void> setView(int year, int month) async {
    int y = year, m = month;
    while (m <= 0) { m += 12; y--; }
    while (m > 12) { m -= 12; y++; }
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

  // ──── occurrence API（替代 eventsOnDate / RecurrenceResolver）──────

  List<EventOccurrence> eventsOn(DateTime day) {
    final engine = OccurrenceEngine(_lunar);
    return engine.eventsOn(events, day);
  }

  List<EventOccurrence> occurrencesBetween(DateTime from, DateTime to) {
    final engine = OccurrenceEngine(_lunar);
    return engine.occurrencesBetween(events, from, to);
  }

  DateTime? nextOccurrence(Event e, DateTime from) {
    return OccurrenceEngine(_lunar).nextOccurrence(e, from);
  }

  // ──── 写操作 ────

  Future<Event> addEvent(EventDraft draft) async {
    return _addInternal(draft);
  }

  Future<Event> _addInternal(EventDraft draft) async {
    final e = Event(
      id: _uuid.v4(),
      title: draft.title,
      type: draft.type,
      anchor: draft.anchor,
      period: draft.period,
      colorTag: draft.colorTag,
      people: draft.people,
      note: draft.note,
      groupId: _activeGroupId,
      createdAt: DateTime.now(),
    );
    _events.add(e);
    // 把 patches upsert 到 global roster
    final people = LabPeopleProvider.current;
    if (people != null) {
      for (final p in draft.people) {
        if (p.name != null) {
          await people.upsertPatch(p, groupId: _activeGroupId);
        }
      }
    }
    await CalendarRepository.instance.saveEvent(e);
    _syncToWidget();
    notifyListeners();
    return e;
  }

  Future<void> updateEvent(Event e) async {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i == -1) return;
    _events[i] = e;
    await CalendarRepository.instance.saveEvent(e);
    _syncToWidget();
    notifyListeners();
  }

  Future<void> removeEvent(String id) async {
    final event = _events.firstWhere((e) => e.id == id, orElse: () => Event(
      id: id, title: '', type: EventType.custom, anchor: const SolarAnchor(year: 1970, month: 1, day: 1),
      period: const OneShotPeriod(), colorTag: ColorTag.gray, groupId: '', createdAt: DateTime.now(),
    ));
    if (event.systemCalendarEventId != null) {
      await CalendarService.deleteEvent(event.systemCalendarEventId!);
    }
    _events.removeWhere((e) => e.id == id);
    await CalendarRepository.instance.deleteEvent(id);
    _syncToWidget();
    notifyListeners();
  }

  /// 批量写入事件（DSL 解析结果用）
  Future<int> importEvents(List<Event> events) async {
    final newOnes = <Event>[];
    for (final e in events) {
      newOnes.add(Event(
        id: e.id,
        title: e.title,
        type: e.type,
        anchor: e.anchor,
        period: e.period,
        colorTag: e.colorTag,
        people: e.people,
        note: e.note,
        createdAt: e.createdAt,
        groupId: _activeGroupId,
        systemCalendarEventId: e.systemCalendarEventId,
      ));
    }
    _events.addAll(newOnes);
    await _saveAll();
    _syncToWidget();
    notifyListeners();
    return newOnes.length;
  }

  /// DSL → 报告
  Future<DslApplyReport> applyDsl(String text) async {
    final parsed = parseCalendarDsl(text);
    final cfg = CalendarConfig.defaultConfig;
    final interp = interpret(parsed.stmts, config: cfg);
    final allErrors = <Object>[
      ...parsed.errors,
      ...interp.errors,
    ];
    var added = 0;
    var skipped = 0;
    for (final d in interp.drafts) {
      try {
        await addEvent(d);
        added++;
      } catch (_) {
        skipped++;
      }
    }
    return DslApplyReport(added: added, skipped: skipped, errors: allErrors);
  }

  /// 导出当前 group 为 DSL。
  String exportDsl() {
    final cfg = CalendarConfig.defaultConfig;
    final people = LabPeopleProvider.current?.allPeople
            .where((p) => p.groupId == _activeGroupId)
            .toList() ??
        const [];
    return exportCalendarDsl(events, people: people, config: cfg);
  }

  // ──── 系统日历同步（保留旧能力）──────

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
    final occ = nextOccurrence(event, DateTime.now());
    final useDate = occ ?? (event.anchor is SolarAnchor
        ? DateTime((event.anchor as SolarAnchor).year,
                  (event.anchor as SolarAnchor).month,
                  (event.anchor as SolarAnchor).day)
        : DateTime.now());
    final systemId = await CalendarService.insertEvent(
      title: event.title,
      description: event.note ?? '',
      year: useDate.year,
      month: useDate.month,
      day: useDate.day,
    );
    if (systemId == null) return false;
    final updated = event.copyWith(systemCalendarEventId: systemId);
    _events[i] = updated;
    await CalendarRepository.instance.saveEvent(updated);
    notifyListeners();
    return true;
  }

  /// birthday 类型事件的人物年龄（保留 API）。
  int? ageOfBirthdayPerson(Event birthdayEvent, DateTime today) {
    if (birthdayEvent.type != EventType.birthday) return null;
    DateTime dob;
    if (birthdayEvent.anchor is SolarAnchor) {
      final a = birthdayEvent.anchor as SolarAnchor;
      dob = DateTime(a.year, a.month, a.day);
    } else if (birthdayEvent.anchor is LunarAnchor) {
      final a = birthdayEvent.anchor as LunarAnchor;
      final s = _lunar.toSolar(a.year, a.month, a.day, isLeap: a.isLeap);
      dob = DateTime(s.year, s.month, s.day);
    } else {
      return null;
    }
    return AgeCalculator.calculate(dob, today);
  }

  // ──── 内部 ────

  Future<void> _loadAll() async {
    final repo = CalendarRepository.instance;
    _events = repo.loadEvents();
    final box = repo.viewState;
    _viewYear = (box.get('viewYear') as int?) ?? DateTime.now().year;
    _viewMonth = (box.get('viewMonth') as int?) ?? DateTime.now().month;
    _syncToWidget();
    notifyListeners();
  }

  Future<void> _saveAll() async {
    final repo = CalendarRepository.instance;
    await repo.clearEvents();
    for (final e in _events) {
      await repo.saveEvent(e);
    }
  }

  void _syncToWidget() {
    final occ = occurrencesBetween(
      DateTime(_viewYear, _viewMonth, 1),
      DateTime(_viewYear, _viewMonth + 1, 0, 23, 59, 59),
    );
    final data = CalendarWidgetData.fromOccurrences(
      year: _viewYear,
      month: _viewMonth,
      occurrences: occ,
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