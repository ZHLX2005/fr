import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';

import '../../domain/anchor.dart';
import '../../domain/event.dart';
import '../../domain/period.dart';
import '../../domain/person.dart';
import '../../domain/person_patch.dart';
import '../../data/event_draft.dart';
import 'dsl_ast.dart';
import 'dsl_errors.dart';
import 'dsl_lexer.dart';

/// 顶层共享人物的"种子"（来自 DSL people 块或顶层 patch）。
class _PersonSeed {
  final String name;
  PersonRelation? relation;
  String? avatar;
  String? note;
  _PersonSeed(this.name, {this.relation, this.avatar, this.note});
}

/// 解释时维护的人物名册。后续任务（LabPeopleProvider.upsertPatch）将基于此 resolve。
class PeopleRoster {
  final Map<String, _PersonSeed> byName;
  PeopleRoster.fromEntries(Iterable<AstPersonEntry> entries)
      : byName = {for (final e in entries) e.name: _parseSeed(e)};

  static _PersonSeed _parseSeed(AstPersonEntry e) {
    final attrs = e.attrs;
    return _PersonSeed(
      e.name,
      relation: _parseRelation(attrs['relation']),
      avatar: attrs['avatar'],
      note: attrs['note'],
    );
  }

  static PersonRelation? _parseRelation(String? s) {
    if (s == null) return null;
    for (final r in PersonRelation.values) {
      if (r.name == s) return r;
    }
    return null;
  }
}

/// 解释结果：EventDraft 列表 + 累积错误。
class InterpretResult {
  final List<EventDraft> drafts;
  final List<DslError> errors;
  const InterpretResult(this.drafts, this.errors);
}

/// 把 AST + people 名册 + 顶层 config 解释成 EventDraft 列表。
InterpretResult interpret(
  List<AstStmt> stmts, {
  PeopleRoster? roster,
  CalendarConfig? config,
}) {
  final cfg = config ?? CalendarConfig.defaultConfig;
  final errors = <DslError>[];
  final drafts = <EventDraft>[];

  // 收集 people 块 + 内联 patch，构造 PeopleRoster
  final personEntries = <AstPersonEntry>[];
  for (final s in stmts) {
    if (s is AstPeopleBlock) {
      personEntries.addAll(s.entries);
    }
  }
  final r = roster ?? PeopleRoster.fromEntries(personEntries);

  final anchorYear = _startYear(cfg);

  for (final s in stmts) {
    if (s is AstEventBlock) {
      final draft = _interpretEvent(s, r, anchorYear, errors);
      if (draft != null) drafts.add(draft);
    }
    if (s is AstEventOneline) {
      final draft = _interpretOneLiner(s, cfg, anchorYear, errors);
      if (draft != null) drafts.add(draft);
    }
  }

  return InterpretResult(drafts, errors);
}

int _startYear(CalendarConfig cfg) {
  final s = cfg.startDateIso;
  return int.parse(s.substring(0, 4));
}

// ───────── event block ─────────

EventDraft? _interpretEvent(
  AstEventBlock eb,
  PeopleRoster roster,
  int anchorYear,
  List<DslError> errors,
) {
  String? typeStr = _valueString(eb.fields['type']);
  final type = _parseType(typeStr);
  String? systemStr = _valueString(eb.fields['system']);
  String? colorStr = _valueString(eb.fields['color']);
  final color = _parseColor(colorStr);
  String? note = _valueString(eb.fields['note']);

  final periodAst = eb.fields['period'];
  if (periodAst is! AstPeriod) {
    errors.add(DslError(eb.pos, 'event "${eb.title}" missing period'));
    return null;
  }
  final built = _buildPeriodAndAnchor(
    periodAst,
    eb,
    systemStr,
    anchorYear,
    errors,
  );
  if (built == null) return null;
  final period = built.period;
  final anchor = built.anchor;

  final patches = <PersonPatch>[];
  final peopleAst = eb.fields['people'];
  if (peopleAst is AstList) {
    for (final entry in peopleAst.items) {
      final patch = _patchFromMap(entry, roster, eb.pos, errors);
      if (patch != null) patches.add(patch);
    }
  }

  return EventDraft(
    title: eb.title,
    type: type,
    anchor: anchor,
    period: period,
    colorTag: color,
    people: patches,
    note: note,
  );
}

// ───────── oneline ─────────

EventDraft? _interpretOneLiner(
  AstEventOneline eo,
  CalendarConfig cfg,
  int anchorYear,
  List<DslError> errors,
) {
  final type = _parseType(eo.attrs['type']);
  final systemStr = eo.attrs['system'];
  final color = _parseColor(eo.attrs['color']);
  final periodStr = eo.dateExprText;
  // oneline 形式：`YYYY-MM-DD`（一次性）或 `yearly:MM-DD` / `yearly-lunar:...` 等
  // 简化：只支持一次性公历 + `yearly:MM-DD`（公历年）
  if (RegExp(r'^\d{4}-\d{1,2}-\d{1,2}$').hasMatch(periodStr)) {
    final d = DateTime.parse(periodStr);
    return EventDraft(
      title: eo.title,
      type: type,
      anchor: AnchorFactory.solar(month: d.month, day: d.day, year: d.year),
      period: PeriodFactory.oneShot(),
      colorTag: color,
      note: eo.attrs['note'],
      people: const [],
    );
  }
  final yearly = RegExp(r'^yearly:(\d{1,2})-(\d{1,2})$').firstMatch(periodStr);
  if (yearly != null) {
    final m = int.parse(yearly.group(1)!);
    final d = int.parse(yearly.group(2)!);
    return EventDraft(
      title: eo.title,
      type: type,
      anchor: AnchorFactory.solar(month: m, day: d, year: anchorYear),
      period: PeriodFactory.yearly(),
      colorTag: color,
      note: eo.attrs['note'],
      people: const [],
    );
  }
  errors.add(DslError(eo.pos, 'unrecognized oneline date expression: "$periodStr"'));
  return null;
}

// ───────── period + anchor ─────────

class _AnchorPeriod {
  final Period period;
  final Anchor anchor;
  const _AnchorPeriod(this.period, this.anchor);
}

class _PeriodKeyWhitelist {
  static const yearly = {'system', 'month', 'day', 'isLeap', 'until', 'count'};
  static const monthlyDay = {'day', 'until', 'count'};
  static const monthlyNth = {'nth', 'weekday', 'until', 'count'};
  static const everyDays = {'days', 'start', 'until', 'count'};
  static const everyWeeks = {'weeks', 'weekdays', 'start', 'until', 'count'};

  static const allowedFor = <String, Set<String>>{
    'yearly': yearly,
    'monthly-day': monthlyDay,
    'monthly-nth': monthlyNth,
    'every-days': everyDays,
    'every-weeks': everyWeeks,
  };
}

_AnchorPeriod? _buildPeriodAndAnchor(
  AstPeriod p,
  AstEventBlock eb,
  String? systemStr,
  int anchorYear,
  List<DslError> errors,
) {
  final allowed = _PeriodKeyWhitelist.allowedFor[p.kind];
  if (allowed != null) {
    for (final k in p.tail.keys) {
      if (!allowed.contains(k)) {
        errors.add(DslError(p.pos, 'illegal period key /$k for kind "${p.kind}"'));
        return null;
      }
    }
  }
  switch (p.kind) {
    case 'once':
      return _AnchorPeriod(
        PeriodFactory.oneShot(),
        AnchorFactory.solar(month: 1, day: 1, year: anchorYear),
      );
    case 'yearly':
      return _yearlyPeriod(p, systemStr, anchorYear, errors);
    case 'monthly-day':
      return _monthlyDayPeriod(p, anchorYear, errors);
    case 'monthly-nth':
      return _monthlyNthPeriod(p, anchorYear, errors);
    case 'every-days':
      return _everyDaysPeriod(p, anchorYear, errors);
    case 'every-weeks':
      return _everyNWeeksPeriod(p, anchorYear, errors);
  }
  errors.add(DslError(p.pos, 'unrecognized period kind: ${p.kind}'));
  return null;
}

_AnchorPeriod _yearlyPeriod(AstPeriod p, String? systemStr, int anchorYear, List<DslError> errors) {
  final m = _intValue(p.tail['month']);
  final d = _intValue(p.tail['day']);
  final sys = systemStr ?? (p.tail['system'] is AstString ? (p.tail['system'] as AstString).text : 'solar');
  final isLeap = _boolValue(p.tail['isLeap']) ?? false;
  if (m == null || d == null) {
    errors.add(DslError(p.pos, 'yearly period requires /month and /day'));
    return _AnchorPeriod(PeriodFactory.yearly(), _invalidAnchor());
  }
  final until = _dateValue(p.tail['until']);
  final count = _intValue(p.tail['count']);
  final period = PeriodFactory.yearly(until: until, count: count);
  if (sys == 'lunar') {
    return _AnchorPeriod(period, AnchorFactory.lunar(month: m, day: d, isLeap: isLeap, year: anchorYear));
  }
  return _AnchorPeriod(period, AnchorFactory.solar(month: m, day: d, year: anchorYear));
}

_AnchorPeriod _monthlyDayPeriod(AstPeriod p, int anchorYear, List<DslError> errors) {
  final d = _intValue(p.tail['day']);
  if (d == null || d < 1 || d > 31) {
    errors.add(DslError(p.pos, 'monthly-day requires /day in 1..31'));
    return _AnchorPeriod(PeriodFactory.monthlyDay(day: 1), _invalidAnchor());
  }
  final until = _dateValue(p.tail['until']);
  final count = _intValue(p.tail['count']);
  return _AnchorPeriod(
    PeriodFactory.monthlyDay(day: d, until: until, count: count),
    AnchorFactory.solar(month: 1, day: d, year: anchorYear),
  );
}

_AnchorPeriod _monthlyNthPeriod(AstPeriod p, int anchorYear, List<DslError> errors) {
  final n = _intValue(p.tail['nth']);
  final weekdayStr = _stringValue(p.tail['weekday']);
  if (n == null || n < 1 || n > 5) {
    errors.add(DslError(p.pos, 'monthly-nth requires /nth in 1..5'));
    return _AnchorPeriod(PeriodFactory.monthlyNthWeekday(n: 1, weekday: 1), _invalidAnchor());
  }
  if (weekdayStr == null) {
    errors.add(DslError(p.pos, 'monthly-nth requires /weekday'));
    return _AnchorPeriod(PeriodFactory.monthlyNthWeekday(n: n, weekday: 1), _invalidAnchor());
  }
  final weekday = _weekdayNum(weekdayStr);
  if (weekday == null) {
    errors.add(DslError(p.pos, 'unrecognized weekday: $weekdayStr'));
    return _AnchorPeriod(PeriodFactory.monthlyNthWeekday(n: n, weekday: 1), _invalidAnchor());
  }
  // 计算首个匹配的 anchor date
  final firstOccurrence = _firstNthWeekdayOnOrAfter(
    DateTime(anchorYear, 1, 1),
    n,
    weekday,
  );
  final until = _dateValue(p.tail['until']);
  final count = _intValue(p.tail['count']);
  return _AnchorPeriod(
    PeriodFactory.monthlyNthWeekday(n: n, weekday: weekday, until: until, count: count),
    AnchorFactory.solar(month: firstOccurrence.month, day: firstOccurrence.day, year: firstOccurrence.year),
  );
}

_AnchorPeriod _everyDaysPeriod(AstPeriod p, int anchorYear, List<DslError> errors) {
  final n = _intValue(p.tail['days']) ?? _intValue(p.tail['n']);
  final start = _dateValue(p.tail['start']);
  if (n == null || n < 1) {
    errors.add(DslError(p.pos, 'every-days requires /days >= 1'));
    return _AnchorPeriod(PeriodFactory.everyNDays(n: 1), _invalidAnchor());
  }
  if (start == null) {
    errors.add(DslError(p.pos, 'every-days requires /start'));
    return _AnchorPeriod(PeriodFactory.everyNDays(n: n), _invalidAnchor());
  }
  final until = _dateValue(p.tail['until']);
  final count = _intValue(p.tail['count']);
  return _AnchorPeriod(
    PeriodFactory.everyNDays(n: n, until: until, count: count),
    AnchorFactory.solar(month: start.month, day: start.day, year: start.year),
  );
}

_AnchorPeriod _everyNWeeksPeriod(AstPeriod p, int anchorYear, List<DslError> errors) {
  final n = _intValue(p.tail['weeks']) ?? _intValue(p.tail['n']);
  final start = _dateValue(p.tail['start']);
  final wdsAst = p.tail['weekdays'];
  final wds = <int>{};
  if (wdsAst is AstList) {
    for (final entry in wdsAst.items) {
      final v = entry['v'];
      if (v is AstString) {
        final w = _weekdayNum(v.text);
        if (w != null) wds.add(w);
      }
    }
  }
  if (n == null || n < 1) {
    errors.add(DslError(p.pos, 'every-weeks requires /weeks >= 1'));
    return _AnchorPeriod(PeriodFactory.everyNWeeks(n: 1, weekdays: const {1}), _invalidAnchor());
  }
  if (start == null) {
    errors.add(DslError(p.pos, 'every-weeks requires /start'));
    return _AnchorPeriod(PeriodFactory.everyNWeeks(n: n, weekdays: wds), _invalidAnchor());
  }
  if (wds.isEmpty) {
    errors.add(DslError(p.pos, 'every-weeks requires /weekdays'));
    return _AnchorPeriod(PeriodFactory.everyNWeeks(n: n, weekdays: const {1}), _invalidAnchor());
  }
  final until = _dateValue(p.tail['until']);
  final count = _intValue(p.tail['count']);
  return _AnchorPeriod(
    PeriodFactory.everyNWeeks(n: n, weekdays: wds, until: until, count: count),
    AnchorFactory.solar(month: start.month, day: start.day, year: start.year),
  );
}

// ───────── helpers ─────────

String? _valueString(AstValue? v) {
  if (v is AstString) return v.text;
  if (v is AstNumber) return v.n.toString();
  if (v is AstBool) return v.b ? 'true' : 'false';
  return null;
}

int? _intValue(AstValue? v) {
  if (v is AstNumber) return v.n;
  if (v is AstString) return int.tryParse(v.text);
  return null;
}

String? _stringValue(AstValue? v) {
  if (v is AstString) return v.text;
  if (v is AstNumber) return v.n.toString();
  return null;
}

bool? _boolValue(AstValue? v) {
  if (v is AstBool) return v.b;
  if (v is AstString) return v.text == 'true';
  return null;
}

DateTime? _dateValue(AstValue? v) {
  if (v is AstString) {
    final s = v.text;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }
  return null;
}

EventType _parseType(String? s) {
  if (s == null) return EventType.custom;
  for (final t in EventType.values) {
    if (t.name == s) return t;
  }
  return EventType.custom;
}

ColorTag _parseColor(String? s) {
  if (s == null) return ColorTag.gray;
  for (final c in ColorTag.values) {
    if (c.name == s) return c;
  }
  return ColorTag.gray;
}

int? _weekdayNum(String s) {
  switch (s) {
    case 'Mon': return 1;
    case 'Tue': return 2;
    case 'Wed': return 3;
    case 'Thu': return 4;
    case 'Fri': return 5;
    case 'Sat': return 6;
    case 'Sun': return 7;
  }
  return int.tryParse(s);
}

DateTime _firstNthWeekdayOnOrAfter(DateTime start, int n, int weekday) {
  // weekday: Mon=1..Sun=7
  var d = start;
  // 先移到第一个 weekday ≥ start
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  // 现在 d.weekday == weekday，d 是当月该 weekday 的第 1 个
  // 跳到第 n 个
  return d.add(Duration(days: 7 * (n - 1)));
}

Anchor _invalidAnchor() =>
    AnchorFactory.solar(month: 1, day: 1, year: 1970);

PersonPatch? _patchFromMap(
  Map<String, AstValue> map,
  PeopleRoster roster,
  Position pos,
  List<DslError> errors,
) {
  final name = _valueString(map['name']);
  if (name == null) {
    errors.add(DslError(pos, 'person patch missing name'));
    return null;
  }
  final relationStr = _valueString(map['relation']);
  PersonRelation? relation;
  if (relationStr != null) {
    for (final r in PersonRelation.values) {
      if (r.name == relationStr) {
        relation = r;
        break;
      }
    }
  }
  final avatar = _valueString(map['avatar']);
  final note = _valueString(map['note']);
  return PersonPatch(name: name, relation: relation, avatarEmoji: avatar, note: note);
}