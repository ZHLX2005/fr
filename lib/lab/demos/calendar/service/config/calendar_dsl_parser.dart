// Calendar DSL parser + exporter (kebab-case: calendar_dsl_parser).
//
// 2-segment DSL: optional `config:` header + event/person lines.
// Re-exports CalendarGroup/CalendarConfig/CalendarDslFullResult/CalendarPersonDraft
// from calendar_config.dart for UI/Provider convenience.

import '../../domain/event.dart';
import '../../domain/person.dart';
import '../../domain/recurrence.dart';
import '../../data/calendar_config.dart';
import 'calendar_dsl_models.dart';

export 'calendar_dsl_models.dart';

DateTime _parseYmd(String s) {
  // Accept YYYY-MM-DD / YYYY/MM/DD / YYYYMMDD.
  final norm = s.replaceAll('/', '-');
  if (RegExp(r'^\d{8}$').hasMatch(norm)) {
    return DateTime(
      int.parse(norm.substring(0, 4)),
      int.parse(norm.substring(4, 6)),
      int.parse(norm.substring(6, 8)),
    );
  }
  return DateTime.parse(norm);
}

int? _parseMonthsDayKey(String s) {
  final m = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  final month = int.parse(m.group(1)!);
  final day = int.parse(m.group(2)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return month * 100 + day;
}

DateTime? _dateFromMonthsDay(int key, int year) {
  final month = key ~/ 100;
  final day = key % 100;
  try {
    return DateTime(year, month, day);
  } catch (_) {
    if (month == 2 && day == 29) return DateTime(year, 2, 28);
    return null;
  }
}

EventType? _parseEventType(String s) {
  for (final t in EventType.values) {
    if (t.name == s) return t;
  }
  return null;
}

ColorTag? _parseColorTag(String s) {
  for (final c in ColorTag.values) {
    if (c.name == s) return c;
  }
  return null;
}

CalendarSystem _parseSystem(String s) =>
    s == 'lunar' ? CalendarSystem.lunar : CalendarSystem.solar;

({int n, DateTime? starting})? _parseEveryDays(String s) {
  // every-N-days REQUIRES starting= anchor (so the parse reflects first occurrence
  // and round-trips losslessly). Without starting, we cannot expand the event
  // meaningfully; reject and let the progressive probe fall through to other forms.
  if (!s.contains('starting=')) return null;
  final m = RegExp(r'^every-(\d+)-days starting=(\d{4}-\d{1,2}-\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  return (n: int.parse(m.group(1)!), starting: _parseYmd(m.group(2)!));
}

({int n, Set<int> weekdays, DateTime? starting})? _parseEveryWeeks(String s) {
  final baseM = RegExp(r'^every-(\d+)-weeks:(.+)$').firstMatch(s);
  if (baseM == null) return null;
  final n = int.parse(baseM.group(1)!);
  final rest = baseM.group(2)!;
  String weekdaysPart = rest;
  DateTime? starting;
  final sM = RegExp(r'^(.+)\s+starting=(\d{4}-\d{1,2}-\d{1,2})$').firstMatch(rest);
  if (sM != null) {
    weekdaysPart = sM.group(1)!;
    starting = _parseYmd(sM.group(2)!);
  }
  const map = {
    'Mon': 1, 'Tue': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6, 'Sun': 7,
  };
  final wd = <int>{};
  for (final token in weekdaysPart.split(',')) {
    final w = map[token.trim()];
    if (w != null) wd.add(w);
  }
  if (wd.isEmpty) return null;
  return (n: n, weekdays: wd, starting: starting);
}

({int day, DateTime? starting})? _parseMonthly(String s) {
  final m = RegExp(r'^monthly:(\d{1,2})(?::starting=(\d{4}-\d{1,2}-\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  if (day < 1 || day > 31) return null;
  return (day: day, starting: m.group(2) == null ? null : _parseYmd(m.group(2)!));
}

({int weekday, int n, DateTime? starting})? _parseNthWeekday(String s) {
  final m = RegExp(
    r'^nth-weekday:(Mon|Tue|Wed|Thu|Fri|Sat|Sun),N=(\d+)(?::starting=(\d{4}-\d{1,2}-\d{1,2}))?$',
  ).firstMatch(s);
  if (m == null) return null;
  const wmap = {
    'Mon': 1, 'Tue': 2, 'Wed': 3, 'Thu': 4, 'Fri': 5, 'Sat': 6, 'Sun': 7,
  };
  final weekday = wmap[m.group(1)!]!;
  final n = int.parse(m.group(2)!);
  if (n < 1 || n > 5) return null;
  return (weekday: weekday, n: n, starting: m.group(3) == null ? null : _parseYmd(m.group(3)!));
}

/// Parsed frequency expression (mapped to Event fields later).
class _ParsedFreq {
  final Recurrence recurrence;
  final int? solarYearOffset;
  final int? lunarMonthsDayKey;
  final int? solarMonthsDayKey;
  final bool lunarIsLeap;
  final int? everyNDays;
  final int? everyNWeeks;
  final Set<int>? everyNWeeksDays;
  final DateTime? everyNWeeksStarting;
  final int? monthlyDay;
  final DateTime? monthlyStarting;
  final int? nthWeekdayDay;
  final int? nthWeekdayN;
  final DateTime? nthWeekdayStarting;
  final DateTime? oneShotSolar;
  final DateTime? oneShotLunar;

  const _ParsedFreq({
    this.recurrence = Recurrence.none,
    this.solarYearOffset,
    this.lunarMonthsDayKey,
    this.solarMonthsDayKey,
    this.lunarIsLeap = false,
    this.everyNDays,
    this.everyNWeeks,
    this.everyNWeeksDays,
    this.everyNWeeksStarting,
    this.monthlyDay,
    this.monthlyStarting,
    this.nthWeekdayDay,
    this.nthWeekdayN,
    this.nthWeekdayStarting,
    this.oneShotSolar,
    this.oneShotLunar,
  });
}

class _ParseResult {
  final _ParsedFreq? freq;
  final String? error;
  _ParseResult({this.freq, this.error});
}

_ParseResult _parseDateExpr(String s) {
  final raw = s.trim();
  if (RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$').hasMatch(raw)) {
    try {
      return _ParseResult(freq: _ParsedFreq(oneShotSolar: _parseYmd(raw)));
    } catch (e) {
      return _ParseResult(error: 'one-shot solar date invalid: $raw ($e)');
    }
  }
  if (raw.startsWith('lunar:') && RegExp(r'^lunar:\d{8}$').hasMatch(raw)) {
    final ymd = raw.substring(6);
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.none,
        oneShotLunar: DateTime(
          int.parse(ymd.substring(0, 4)),
          int.parse(ymd.substring(4, 6)),
          int.parse(ymd.substring(6, 8)),
        ),
      ),
    );
  }
  if (raw.startsWith('yearly-solar:')) {
    final mdk = _parseMonthsDayKey(raw.substring(13));
    if (mdk == null) {
      return _ParseResult(error: 'yearly-solar:MM-DD incomplete: $raw');
    }
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.yearly,
        solarMonthsDayKey: mdk,
      ),
    );
  }
  if (raw.startsWith('yearly-lunar:')) {
    final mdk = _parseMonthsDayKey(raw.substring(13));
    if (mdk == null) return _ParseResult(error: 'yearly-lunar:MMDD invalid: $raw');
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.yearlyLunarAuto,
        lunarMonthsDayKey: mdk,
      ),
    );
  }
  final offM =
      RegExp(r'^yearly-solar-offset:(-?\d+):(\d{1,2}-\d{1,2})$').firstMatch(raw);
  if (offM != null) {
    final offset = int.parse(offM.group(1)!);
    final mdk = _parseMonthsDayKey(offM.group(2)!);
    if (mdk == null) return _ParseResult(error: 'yearly-solar-offset invalid: $raw');
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.manual,
        solarMonthsDayKey: mdk,
        solarYearOffset: offset,
      ),
    );
  }
  if (raw.startsWith('every-') && raw.contains('-days')) {
    final ed = _parseEveryDays(raw);
    if (ed == null) return _ParseResult(error: 'every-N-days invalid: $raw');
    return _ParseResult(freq: _ParsedFreq(
      everyNDays: ed.n,
      everyNWeeksStarting: ed.starting,
    ));
  }
  if (raw.startsWith('every-') && raw.contains('-weeks')) {
    final ew = _parseEveryWeeks(raw);
    if (ew == null) return _ParseResult(error: 'every-N-weeks invalid: $raw');
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.yearly,
        everyNWeeks: ew.n,
        everyNWeeksDays: ew.weekdays,
        everyNWeeksStarting: ew.starting,
      ),
    );
  }
  if (raw.startsWith('monthly:')) {
    final m = _parseMonthly(raw);
    if (m == null) return _ParseResult(error: 'monthly:DD invalid: $raw');
    // monthlyDay stores raw day-of-month; Event uses month=any, day=raw.
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.yearly,
        monthlyDay: m.day,
        monthlyStarting: m.starting,
      ),
    );
  }
  if (raw.startsWith('nth-weekday:')) {
    final n = _parseNthWeekday(raw);
    if (n == null) return _ParseResult(error: 'nth-weekday invalid: $raw');
    return _ParseResult(
      freq: _ParsedFreq(
        recurrence: Recurrence.yearly,
        nthWeekdayDay: n.weekday,
        nthWeekdayN: n.n,
        nthWeekdayStarting: n.starting,
      ),
    );
  }
  return _ParseResult(error: 'unrecognized date/freq: $raw');
}

Map<String, String> _parseAttrs(String rest) {
  final map = <String, String>{};
  final noteRe = RegExp(r'''note=(?:"([^"]*)"|'([^']*)'|(\S+))''');
  String remaining = rest;
  for (final m in noteRe.allMatches(rest)) {
    map['note'] = m.group(1) ?? m.group(2) ?? m.group(3)!;
    remaining = remaining.replaceFirst(m.group(0)!, '');
  }
  for (final token in remaining.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    final eq = token.indexOf('=');
    if (eq < 0) continue;
    final k = token.substring(0, eq);
    var v = token.substring(eq + 1);
    if ((v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"))) {
      v = v.substring(1, v.length - 1);
    }
    map[k] = v;
  }
  return map;
}

/// Parse the full DSL text.
CalendarDslFullResult parseCalendarDsl(String input) {
  final events = <Event>[];
  final persons = <CalendarPersonDraft>[];
  CalendarConfig? config;
  final errors = <String>[];
  final now = DateTime.now();
  final fallbackStart =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final personIdByName = <String, String>{};

  for (final rawLine in input.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    if (line.startsWith('config:')) {
      final body = line.substring(7).trim();
      final cfg = <String, String>{};
      for (final token in body.split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        final eq = token.indexOf('=');
        if (eq < 0) continue;
        cfg[token.substring(0, eq)] = token.substring(eq + 1);
      }
      config = CalendarConfig(
        defaultSystem: cfg['default-system'] ?? 'solar',
        startDateIso: cfg['start'] ?? fallbackStart,
        defaultColorTag: cfg['default-color'] ?? 'gray',
      );
      continue;
    }

    if (line.startsWith('person ')) {
      final body = line.substring(7).trim();
      if (body.isEmpty) {
        errors.add('person line is empty');
        continue;
      }
      final firstSpace = body.indexOf(' ');
      String name;
      Map<String, String> attrs;
      if (firstSpace < 0) {
        name = body;
        attrs = {};
      } else {
        name = body.substring(0, firstSpace).trim();
        attrs = _parseAttrs(body.substring(firstSpace + 1));
      }
      if (name.isEmpty) {
        errors.add('person name is empty');
        continue;
      }
      final id = attrs['id'] ?? 'p_${personIdByName.length}_${name.hashCode.abs()}';
      if (personIdByName.containsKey(name)) {
        errors.add('duplicate person name: $name');
        continue;
      }
      personIdByName[name] = id;
      persons.add(CalendarPersonDraft(
        id: id,
        name: name,
        relation: attrs['relation'],
        avatarEmoji: attrs['avatar'],
        note: attrs['note'],
      ));
      continue;
    }

    if (!line.contains('@')) {
      errors.add('event line missing @: $line');
      continue;
    }
    final atIdx = line.indexOf('@');
    final title = line.substring(0, atIdx).trim();
    final rest = line.substring(atIdx + 1).trim();
    _ParseResult? parsed;
    int dateEndIdx = -1;
    for (int i = rest.length; i >= 0; i--) {
      final probe = rest.substring(0, i);
      final r = _parseDateExpr(probe);
      if (r.error == null) {
        parsed = r;
        dateEndIdx = i;
        break;
      }
    }
    if (parsed == null || parsed.error != null) {
      errors.add('event line parse failed: $line (${parsed?.error ?? 'date expression unrecognized'})');
      continue;
    }
    final attrs = _parseAttrs(rest.substring(dateEndIdx).trim());
    final freq = parsed.freq!;
    if (title.isEmpty) {
      errors.add('event title empty: $line');
      continue;
    }
    final type = _parseEventType(attrs['type'] ?? 'custom') ?? EventType.custom;
    final sys = attrs.containsKey('system')
        ? _parseSystem(attrs['system']!)
        : (freq.recurrence == Recurrence.yearlyLunarAuto || freq.oneShotLunar != null)
            ? CalendarSystem.lunar
            : (freq.recurrence == Recurrence.manual ||
                    freq.recurrence == Recurrence.yearly ||
                    freq.oneShotSolar != null)
                ? CalendarSystem.solar
                : (config?.defaultSystem == 'lunar'
                    ? CalendarSystem.lunar
                    : CalendarSystem.solar);
    final color = _parseColorTag(attrs['color'] ?? '') ?? ColorTag.gray;
    final personName = attrs['person'];
    final personId = personName == null ? null : personIdByName[personName];
    if (personName != null && personId == null) {
      errors.add('event references undefined person: $personName (line: $line)');
    }
    DateTime? solarOneShot;
    int? year;
    int? month;
    int? day;
    bool isLeap = false;
    int? lunarAnchorYear;
    int? solarYearOffset = freq.solarYearOffset;
    if (freq.oneShotSolar != null) {
      solarOneShot = freq.oneShotSolar;
      year = solarOneShot!.year;
      month = solarOneShot.month;
      day = solarOneShot.day;
    } else if (freq.oneShotLunar != null) {
      year = freq.oneShotLunar!.year;
      month = freq.oneShotLunar!.month;
      day = freq.oneShotLunar!.day;
      isLeap = false;
      lunarAnchorYear = year;
    } else if (freq.lunarMonthsDayKey != null || freq.solarMonthsDayKey != null) {
      final mdk = freq.lunarMonthsDayKey ?? freq.solarMonthsDayKey!;
      month = mdk ~/ 100;
      day = mdk % 100;
      isLeap = false;
      final start = config?.startDateIso ?? fallbackStart;
      year = int.parse(start.substring(0, 4));
      if (freq.recurrence == Recurrence.yearlyLunarAuto) {
        lunarAnchorYear = year;
      }
    } else if (freq.monthlyDay != null) {
      // monthly:DD — first-occurrence day-of-month is monthlyDay.
      final start = config?.startDateIso ?? fallbackStart;
      year = int.parse(start.substring(0, 4));
      month = 1; // monthly: 月份不固定,1 占位（由 Resolver 在每次发生推算）
      day = freq.monthlyDay!;
    } else if (freq.everyNDays != null) {
      // every-N-days — anchor from freq.everyNWeeksStarting if set, else from config start.
      final start =
          freq.everyNWeeksStarting ??
              (config?.startDateIso != null
                  ? DateTime.parse(config!.startDateIso!)
                  : DateTime(now.year, now.month, now.day));
      year = start.year;
      month = start.month;
      day = start.day;
    } else {
      // Freq expressions (every-N-days/weeks/monthly/nth-weekday): use start year
      // as first occurrence year. Precise first-occurrence date resolved at
      // Provider add time.
      final start = config?.startDateIso ?? fallbackStart;
      year = int.parse(start.substring(0, 4));
      month = 1;
      day = 1;
    }
    final id = 'e_${DateTime.now().microsecondsSinceEpoch}_${events.length}';
    final event = Event(
      id: id,
      type: type,
      title: title,
      system: sys,
      year: year ?? now.year,
      month: month ?? 1,
      day: day ?? 1,
      isLeap: isLeap,
      solarYearOffset: solarYearOffset,
      recurrence: freq.recurrence,
      personId: personId,
      colorTag: color,
      note: attrs['note'],
      createdAt: now,
      lunarAnchorYear: lunarAnchorYear,
      everyNDays: freq.everyNDays,
    );
    events.add(event);
  }

  return CalendarDslFullResult(
    events: events,
    persons: persons,
    config: config,
    errors: errors,
  );
}

/// Export current group events to DSL text (highly deterministic, round-trip).
String exportCalendarDsl(
  List<Event> events, {
  List<CalendarPersonDraft> persons = const [],
  CalendarConfig? config,
}) {
  final buf = StringBuffer();
  final cfg = config ?? CalendarConfig.defaultConfig;
  buf.writeln(
    'config: default-system=${cfg.defaultSystem} '
    'default-color=${cfg.defaultColorTag} start=${cfg.startDateIso}',
  );
  if (persons.isNotEmpty) {
    buf.writeln();
    for (final p in persons) {
      buf.writeln('person ${p.name} '
          'relation=${p.relation ?? "other"} '
          'avatar=${p.avatarEmoji ?? "🙂"}');
    }
  }
  buf.writeln();
  for (final e in events) {
    final dateExpr = _exportDateExpr(e);
    final attrs = <String>[];
    attrs.add('type=${e.type.name}');
    if (e.recurrence != Recurrence.none) {
      attrs.add('recurrence=${_recurrenceName(e.recurrence)}');
    }
    if (e.everyNDays != null) {
      attrs.add('everyNDays=${e.everyNDays}');
    }
    if (e.system == CalendarSystem.lunar) attrs.add('system=lunar');
    if (e.personId != null) attrs.add('person=${e.personId}');
    if (e.colorTag != ColorTag.gray) attrs.add('color=${e.colorTag.name}');
    if (e.note != null && e.note!.isNotEmpty) attrs.add('note=${e.note}');
    buf.writeln('${e.title} @ $dateExpr ${attrs.join(" ")}');
  }
  return buf.toString();
}

String _exportDateExpr(Event e) {
  final y = e.year.toString().padLeft(4, '0');
  final m = e.month.toString().padLeft(2, '0');
  final d = e.day.toString().padLeft(2, '0');
  if (e.everyNDays != null) {
    return 'every-${e.everyNDays}-days starting=$y-$m-$d';
  }
  if (e.recurrence == Recurrence.yearly) {
    return 'yearly-solar:$m-$d';
  }
  if (e.recurrence == Recurrence.yearlyLunarAuto) {
    return 'yearly-lunar:$m$d';
  }
  if (e.recurrence == Recurrence.manual) {
    final off = e.solarYearOffset ?? 0;
    return 'yearly-solar-offset:$off:$m-$d';
  }
  return '$y-$m-$d';
}

String _recurrenceName(Recurrence r) {
  switch (r) {
    case Recurrence.none:
      return 'none';
    case Recurrence.yearly:
      return 'yearly';
    case Recurrence.yearlyLunarAuto:
      return 'yearly-lunar';
    case Recurrence.manual:
      return 'manual';
  }
}
