import '../../data/calendar_config.dart';
import '../../domain/event.dart';
import '../../domain/anchor.dart';
import '../../domain/period.dart';
import '../../domain/person.dart';
import '../../domain/person_patch.dart';

/// 把 `List<Event>`（当前 group）+ 可选 `people` + config 序列化成 DSL 文本。
///
/// 周期事件走 block 形式 `event "title" { period = ... }`；
/// 一次性事件走 one-liner `"title" @ YYYY-MM-DD`。
String exportCalendarDsl(
  List<Event> events, {
  List<Person> people = const [],
  CalendarConfig? config,
}) {
  final buf = StringBuffer();
  final cfg = config ?? CalendarConfig.defaultConfig;
  buf.writeln('config { default-system=${cfg.defaultSystem} start=${cfg.startDateIso} default-color=${cfg.defaultColorTag} }');
  if (people.isNotEmpty) {
    buf.writeln();
    buf.writeln('people {');
    for (final p in people) {
      buf.writeln('  "${_escape(p.name)}" { relation=${p.relation.name} avatar=${_escape(p.avatarEmoji ?? "🙂")} }');
    }
    buf.writeln('}');
  }
  if (events.isNotEmpty) buf.writeln();
  for (final e in events) {
    if (e.period is OneShotPeriod) {
      final a = e.anchor;
      final ymd = a is SolarAnchor
          ? '${a.year.toString().padLeft(4, '0')}-${a.month.toString().padLeft(2, '0')}-${a.day.toString().padLeft(2, '0')}'
          : '1970-01-01';
      buf.writeln('"${_escape(e.title)}" @ $ymd type=${e.type.name} color=${e.colorTag.name}');
    } else {
      buf.writeln(_exportEventBlock(e));
    }
  }
  return buf.toString();
}

String _exportEventBlock(Event e) {
  final buf = StringBuffer();
  buf.write('event "${_escape(e.title)}" {\n');
  buf.writeln('  type=${e.type.name}');
  buf.writeln('  system=${e.anchor is LunarAnchor ? "lunar" : "solar"}');
  buf.writeln('  period=${_exportPeriod(e.period, e.anchor)}');
  if (e.colorTag != ColorTag.gray) buf.writeln('  color=${e.colorTag.name}');
  if (e.people.isNotEmpty) {
    buf.writeln('  people=[${_exportPeople(e.people)}]');
  }
  if (e.note != null && e.note!.isNotEmpty) buf.writeln('  note=${_escape(e.note!)}');
  buf.write('}');
  return buf.toString();
}

String _exportPeriod(Period p, Anchor a) {
  if (p is YearlyPeriod) {
    final sys = a is LunarAnchor ? 'lunar' : 'solar';
    final tail = <String>['/system=$sys'];
    if (a is LunarAnchor) {
      tail.add('/month=${a.month.toString().padLeft(2, '0')}');
      tail.add('/day=${a.day.toString().padLeft(2, '0')}');
      if (a.isLeap) tail.add('/isLeap=true');
    } else if (a is SolarAnchor) {
      tail.add('/month=${a.month.toString().padLeft(2, '0')}');
      tail.add('/day=${a.day.toString().padLeft(2, '0')}');
    }
    _appendUntilCount(p.until, p.count, tail);
    return 'yearly ${tail.join(' ')}';
  }
  if (p is MonthlyDayPeriod) {
    final tail = <String>['/day=${p.day}'];
    _appendUntilCount(p.until, p.count, tail);
    return 'monthly-day ${tail.join(' ')}';
  }
  if (p is MonthlyNthWeekdayPeriod) {
    final tail = <String>[
      '/nth=${p.n}',
      '/weekday=${_weekdayName(p.weekday)}',
    ];
    _appendUntilCount(p.until, p.count, tail);
    return 'monthly-nth ${tail.join(' ')}';
  }
  if (p is EveryNDaysPeriod) {
    final tail = <String>[
      '/days=${p.n}',
      '/start=${_ymd(p.until ?? DateTime.now())}', // 仅在没有 anchor 时退而求其次
    ];
    _appendUntilCount(p.until, p.count, tail);
    return 'every-days ${tail.join(' ')}';
  }
  if (p is EveryNWeeksPeriod) {
    final tail = <String>[
      '/weeks=${p.n}',
      '/weekdays=${p.weekdays.map(_weekdayName).join(',')}',
      '/start=${_ymd(DateTime.now())}', // 占位；真实 anchor 在 Event.anchor
    ];
    _appendUntilCount(p.until, p.count, tail);
    return 'every-weeks ${tail.join(' ')}';
  }
  return 'once';
}

void _appendUntilCount(DateTime? until, int? count, List<String> tail) {
  if (until != null) tail.add('/until=${_ymd(until)}');
  if (count != null) tail.add('/count=$count');
}

String _exportPeople(List<PersonPatch> patches) {
  return patches.map((p) {
    final buf = StringBuffer('{');
    final parts = <String>[];
    if (p.name != null) parts.add('name="${_escape(p.name!)}"');
    if (p.relation != null) parts.add('relation=${p.relation!.name}');
    if (p.avatarEmoji != null) parts.add('avatar="${_escape(p.avatarEmoji!)}"');
    if (p.note != null) parts.add('note="${_escape(p.note!)}"');
    buf.write(parts.join(' '));
    buf.write('}');
    return buf.toString();
  }).join(', ');
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _weekdayName(int n) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (n < 1 || n > 7) return 'Mon';
  return names[n - 1];
}

String _escape(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');