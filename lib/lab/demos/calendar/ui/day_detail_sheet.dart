import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/calendar_config.dart';
import '../data/event_draft.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/anchor.dart';
import '../domain/event.dart';
import '../domain/period.dart';
import '../domain/person.dart';
import '../domain/person_patch.dart';
import '../lunar_adapter.dart';
import 'widgets/chip_choice.dart';
import 'widgets/paper_button.dart';

/// 当日事件 sheet（看+新建+编辑 inline）
///
/// 接收 Provider 实例作为构造参数，避免依赖 InheritedWidget scope
/// （因为 showModalBottomSheet 推出来的 route 是独立的 InheritedWidget 树）
class DayDetailSheet extends StatelessWidget {
  final DateTime date;
  final LabCalendarProvider cal;
  final LabPeopleProvider people;

  const DayDetailSheet({
    super.key,
    required this.date,
    required this.cal,
    required this.people,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final events = cal.eventsOn(date);

        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 16,
          ),
          decoration: BoxDecoration(
            // §0.1：底部表单 sheet 顶部大色块容器走 bgCard 浅主题色。
            color: pp.bgCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${date.year}年${date.month}月${date.day}日',
                          style: AppText.title(),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lunarLabel(date),
                          style: AppText.caption(),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: pp.inkMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: pp.line),
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('暂无事件',
                      style: AppText.body(color: pp.inkMuted)),
                )
              else
                ...events.map(
                  (o) => _EventRow(
                    event: o.event,
                    cal: cal,
                    people: people,
                    personName: o.event.people.isNotEmpty
                        ? o.event.people.first.name
                        : null,
                  ),
                ),
              const SizedBox(height: 12),
              PaperSecondaryButton(
                icon: Icons.add_rounded,
                label: '新建事件',
                onPressed: () => _openEventForm(context, null),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openEventForm(BuildContext context, Event? existing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EventFormSheet(date: date, existing: existing, cal: cal, people: people),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Event event;
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  final String? personName;
  final VoidCallback? onDeleted;
  const _EventRow({
    required this.event,
    required this.cal,
    required this.people,
    this.personName,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    final color = _hexToColor(event.colorTag.hex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => EventFormSheet(
              date: _anchorDate(event),
              existing: event,
              cal: cal,
              people: people,
            ),
          ),
        ),
        onLongPress: () => _confirmDelete(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: AppText.body()),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _typeNameOf(event.type),
                        event.anchor is SolarAnchor ? '公历' : '农历',
                        if (personName != null) personName!,
                      ].join(' · '),
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              if (event.systemCalendarEventId != null)
                Icon(Icons.cloud_done_outlined,
                    size: 14, color: pp.inkMuted),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: pp.inkMuted,
                onPressed: () => _confirmDelete(context),
                tooltip: '删除',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final pp = PaperPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pp.bgElevated,
        title: Text('删除事件', style: AppText.title()),
        content: Text(
          '确定要删除"${event.title}"？',
          style: AppText.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: pp.today),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await cal.removeEvent(event.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Color _hexToColor(String hex) {
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.tryParse(s, radix: 16) ?? 0;
    return Color(0xFF000000 | v);
  }
}

/// Resolve the Event's anchor to a DateTime for form prefill.
DateTime _anchorDate(Event e) {
  final a = e.anchor;
  if (a is SolarAnchor) return DateTime(a.year, a.month, a.day);
  if (a is LunarAnchor) {
    try {
      final s = LunarAdapter().toSolar(a.year, a.month, a.day, isLeap: a.isLeap);
      return DateTime(s.year, s.month, s.day);
    } catch (_) {
      return DateTime(a.year, a.month, a.day);
    }
  }
  return DateTime.now();
}

/// 类型中文映射（顶层函数，避免重复定义）
String _typeNameOf(EventType t) {
  switch (t) {
    case EventType.birthday:
      return '生日';
    case EventType.anniversary:
      return '纪念日';
    case EventType.countdown:
      return '倒计时';
    case EventType.holiday:
      return '节日';
    case EventType.task:
      return '待办';
    case EventType.custom:
      return '自定义';
  }
}

/// 公历日期 → 中文"农历 X 年 X 月 X" + 生肖
String _lunarLabel(DateTime solar) {
  final l = LunarAdapter().fromSolar(solar);
  final zodiac = LunarAdapter().zodiacOf(solar);
  final leap = l.isLeap ? '闰' : '';
  return '农历 ${l.year} 年 $leap${l.month} 月 ${l.day} · $zodiac';
}

/// 用户在表单里选定的周期种类。
enum _PeriodKind { once, yearly, monthlyDay, monthlyNthWeekday, everyNDays }

extension on _PeriodKind {
  String get label => switch (this) {
        _PeriodKind.once => '仅一次',
        _PeriodKind.yearly => '每年',
        _PeriodKind.monthlyDay => '每月某日',
        _PeriodKind.monthlyNthWeekday => '每月第N个星期X',
        _PeriodKind.everyNDays => '每N天',
      };
}

/// 根据已有 Event.period 推断显示哪种 kind。
_PeriodKind _kindFromEvent(Event e) {
  final p = e.period;
  if (p is OneShotPeriod) return _PeriodKind.once;
  if (p is YearlyPeriod) return _PeriodKind.yearly;
  if (p is MonthlyDayPeriod) return _PeriodKind.monthlyDay;
  if (p is MonthlyNthWeekdayPeriod) return _PeriodKind.monthlyNthWeekday;
  if (p is EveryNDaysPeriod) return _PeriodKind.everyNDays;
  if (p is EveryNWeeksPeriod) return _PeriodKind.everyNDays; // 不在表单支持范围，回退
  return _PeriodKind.once;
}

/// 内嵌的事件表单（新建/编辑）
class EventFormSheet extends StatefulWidget {
  final DateTime date;
  final Event? existing;
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  const EventFormSheet({
    super.key,
    required this.date,
    required this.cal,
    required this.people,
    this.existing,
  });

  @override
  State<EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends State<EventFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late EventType _type;
  late ColorTag _color;
  late CalendarSystem _system;
  late String? _personName;

  // Period editor state
  late _PeriodKind _periodKind;
  late int _monthlyDay; // 1..31
  late int _nth; // 1..5
  late int _weekday; // 1=Mon .. 7=Sun
  late int _everyNDays; // ≥ 1
  late DateTime _everyNStart;
  late bool _isLeap; // 仅农历 + yearly/monthly-day 时相关

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? EventType.task;
    _color = e?.colorTag ?? ColorTag.gray;
    _system = e?.anchor is LunarAnchor ? CalendarSystem.lunar : CalendarSystem.solar;
    _personName = (e?.people.isNotEmpty ?? false) ? e!.people.first.name : null;

    final initialAnchor = e?.anchor;
    _isLeap = initialAnchor is LunarAnchor && initialAnchor.isLeap;
    _periodKind = e == null ? _PeriodKind.once : _kindFromEvent(e);
    _monthlyDay = (initialAnchor is SolarAnchor)
        ? initialAnchor.day
        : (initialAnchor is LunarAnchor ? initialAnchor.day : widget.date.day);
    final p = e?.period;
    if (p is MonthlyNthWeekdayPeriod) {
      _nth = p.n;
      _weekday = p.weekday;
    } else {
      // 默认值：第几个 = ((day-1) / 7).floor() + 1；weekday 沿用 widget.date
      final dayOfMonth = widget.date.day;
      _nth = ((dayOfMonth - 1) ~/ 7) + 1;
      _weekday = widget.date.weekday;
    }
    if (p is EveryNDaysPeriod) {
      _everyNDays = p.n;
      final a = e!.anchor;
      _everyNStart = a is SolarAnchor
          ? DateTime(a.year, a.month, a.day)
          : widget.date;
    } else {
      _everyNDays = 4;
      _everyNStart = widget.date;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;

    final cal = widget.cal;
    final anchor = _buildAnchor();
    final period = _buildPeriod();

    final people = <PersonPatch>[];
    if (_personName != null && _personName!.isNotEmpty) {
      PersonRelation? relation;
      for (final p in widget.people.allPeople) {
        if (p.name == _personName && p.groupId == widget.cal.activeGroupId) {
          relation = p.relation;
          break;
        }
      }
      people.add(PersonPatch(name: _personName, relation: relation));
    }
    final draft = EventDraft(
      title: _title.text,
      type: _type,
      anchor: anchor,
      period: period,
      colorTag: _color,
      people: people,
      note: _note.text.isEmpty ? null : _note.text,
    );
    if (widget.existing != null) {
      await cal.updateEvent(widget.existing!.copyWith(
        title: draft.title,
        type: draft.type,
        anchor: draft.anchor,
        period: draft.period,
        colorTag: draft.colorTag,
        people: draft.people,
        note: draft.note,
      ));
    } else {
      await cal.addEvent(draft);
    }
    if (mounted) Navigator.pop(context);
  }

  Anchor _buildAnchor() {
    final y = widget.date.year;
    final m = widget.date.month;
    final d = widget.date.day;
    switch (_periodKind) {
      case _PeriodKind.once:
        return _system == CalendarSystem.lunar
            ? AnchorFactory.lunar(month: m, day: d, isLeap: _isLeap, year: y)
            : AnchorFactory.solar(month: m, day: d, year: y);
      case _PeriodKind.yearly:
        // 每年：anchor 用 widget.date 的 m/d；lunar 时按用户选的是否闰月
        return _system == CalendarSystem.lunar
            ? AnchorFactory.lunar(month: m, day: d, isLeap: _isLeap, year: y)
            : AnchorFactory.solar(month: m, day: d, year: y);
      case _PeriodKind.monthlyDay:
        // 月日：m 占位无所谓（engine 用 period.monthlyDay.day + 每月推算），
        // 这里 m=1 是惯例；lunar 时把用户选的天作为 lunar m/d
        if (_system == CalendarSystem.lunar) {
          return AnchorFactory.lunar(month: m, day: _monthlyDay, isLeap: _isLeap, year: y);
        }
        return AnchorFactory.solar(month: 1, day: _monthlyDay, year: y);
      case _PeriodKind.monthlyNthWeekday:
        // 引擎用 month=1 占位，实际 day 由 period.monthlyDay 在 engine 里推算
        return AnchorFactory.solar(month: 1, day: 1, year: y);
      case _PeriodKind.everyNDays:
        final s = _everyNStart;
        return _system == CalendarSystem.lunar
            ? AnchorFactory.lunar(month: s.month, day: s.day, isLeap: false, year: s.year)
            : AnchorFactory.solar(month: s.month, day: s.day, year: s.year);
    }
  }

  Period _buildPeriod() {
    switch (_periodKind) {
      case _PeriodKind.once:
        return PeriodFactory.oneShot();
      case _PeriodKind.yearly:
        return PeriodFactory.yearly();
      case _PeriodKind.monthlyDay:
        return PeriodFactory.monthlyDay(day: _monthlyDay);
      case _PeriodKind.monthlyNthWeekday:
        return PeriodFactory.monthlyNthWeekday(n: _nth, weekday: _weekday);
      case _PeriodKind.everyNDays:
        return PeriodFactory.everyNDays(n: _everyNDays);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return Scaffold(
      backgroundColor: pp.bg,
      appBar: AppBar(
        backgroundColor: pp.bg,
        elevation: 0,
        title: Text(widget.existing == null ? '新建事件' : '编辑事件', style: AppText.title()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: pp.line, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.date.year}年${widget.date.month}月${widget.date.day}日',
                  style: AppText.title(),
                ),
                const SizedBox(height: 2),
                Text(_lunarLabel(widget.date), style: AppText.caption()),
              ],
            ),
          ),
          _PaperField(
            controller: _title,
            label: '标题',
            hint: '事件标题',
          ),
          ChipChoice<EventType>(
            label: '类型',
            values: EventType.values.toList(),
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
            displayName: _typeName,
          ),
          ChipChoice<String?>(
            label: '关联人',
            values: [null, ...widget.people.people.map((p) => p.name)],
            selected: _personName,
            onChanged: (v) => setState(() => _personName = v),
            displayName: (v) => v ?? '不关联',
          ),
          // 周期类型选择
          _SectionLabel(label: '周期'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _PeriodKind.values.map((k) {
              final selected = k == _periodKind;
              return GestureDetector(
                onTap: () => setState(() => _periodKind = k),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? pp.accent.withValues(alpha: 0.15) : pp.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? pp.accent : pp.line,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    k.label,
                    style: AppText.body(
                      color: selected ? pp.accent : pp.ink,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // 周期参数
          _buildPeriodParams(pp),
          const SizedBox(height: 12),
          // 历法
          ChipChoice<CalendarSystem>(
            label: '历法',
            values: CalendarSystem.values.toList(),
            selected: _system,
            onChanged: (v) => setState(() => _system = v),
            displayName: (s) => s == CalendarSystem.solar ? '公历' : '农历',
          ),
          if (_system == CalendarSystem.lunar &&
              (_periodKind == _PeriodKind.yearly ||
                  _periodKind == _PeriodKind.monthlyDay))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _isLeap,
                    onChanged: (v) => setState(() => _isLeap = v ?? false),
                  ),
                  const Text('闰月'),
                ],
              ),
            ),
          ChipChoice<ColorTag>(
            label: '颜色',
            values: ColorTag.values.toList(),
            selected: _color,
            onChanged: (v) => setState(() => _color = v),
            displayName: _colorName,
          ),
          _PaperField(
            controller: _note,
            label: '备注',
            hint: '可选',
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: pp.accent,
              backgroundColor: pp.bgElevated,
              side: BorderSide(
                color: pp.accent.withValues(alpha: 0.5),
                width: 1.5,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 中文显示映射
  String _typeName(EventType t) {
    switch (t) {
      case EventType.birthday:
        return '生日';
      case EventType.anniversary:
        return '纪念日';
      case EventType.countdown:
        return '倒计时';
      case EventType.holiday:
        return '节日';
      case EventType.task:
        return '待办';
      case EventType.custom:
        return '自定义';
    }
  }

  String _recName(bool yearly) => yearly ? '每年' : '仅一次';
  // ignore: unused_element
  // (kept for potential reuse; the bool chip was replaced by kind selector)
  String _colorName(ColorTag c) {
    switch (c) {
      case ColorTag.gray:
        return '雾灰';
      case ColorTag.red:
        return '朱砂';
      case ColorTag.orange:
        return '橘黄';
      case ColorTag.amber:
        return '黄土';
      case ColorTag.sage:
        return '青苔';
      case ColorTag.teal:
        return '深青';
      case ColorTag.indigo:
        return '靛蓝';
      case ColorTag.plum:
        return '紫梅';
    }
  }

  /// 根据当前 _periodKind 渲染对应的参数输入。
  Widget _buildPeriodParams(PaperPalette pp) {
    switch (_periodKind) {
      case _PeriodKind.once:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '仅在 ${widget.date.year}-${_pad2(widget.date.month)}-${_pad2(widget.date.day)} 发生',
            style: AppText.caption(color: pp.inkMuted),
          ),
        );
      case _PeriodKind.yearly:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '每年 ${widget.date.month} 月 ${widget.date.day} 日${_system == CalendarSystem.lunar ? (_isLeap ? '（闰）' : '') : ''}',
            style: AppText.caption(color: pp.inkMuted),
          ),
        );
      case _PeriodKind.monthlyDay:
        return Row(
          children: [
            const Text('每月 '),
            SizedBox(
              width: 60,
              child: TextField(
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: _monthlyDay.toString()),
                onSubmitted: _onMonthlyDayChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Text(' 日（1-31，超月份跳过）'),
          ],
        );
      case _PeriodKind.monthlyNthWeekday:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('第 '),
                SizedBox(
                  width: 50,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _nth.toString()),
                    onSubmitted: _onNthChanged,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Text(' 个 '),
              ],
            ),
            const SizedBox(height: 8),
            ChipChoice<int>(
              label: '星期',
              values: const [1, 2, 3, 4, 5, 6, 7],
              selected: _weekday,
              onChanged: (v) => setState(() => _weekday = v),
              displayName: _weekdayShort,
            ),
          ],
        );
      case _PeriodKind.everyNDays:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('每 '),
                SizedBox(
                  width: 50,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _everyNDays.toString()),
                    onSubmitted: _onEveryNDaysChanged,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Text(' 天（weekday 无关，从选定日期起算）'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('起始日：'),
                TextButton(
                  onPressed: _pickStartDate,
                  child: Text('${_everyNStart.year}-${_pad2(_everyNStart.month)}-${_pad2(_everyNStart.day)}'),
                ),
              ],
            ),
          ],
        );
    }
  }

  void _onMonthlyDayChanged(String v) {
    final n = int.tryParse(v);
    if (n != null && n >= 1 && n <= 31) {
      setState(() => _monthlyDay = n);
    }
  }

  void _onNthChanged(String v) {
    final n = int.tryParse(v);
    if (n != null && n >= 1 && n <= 5) {
      setState(() => _nth = n);
    }
  }

  void _onEveryNDaysChanged(String v) {
    final n = int.tryParse(v);
    if (n != null && n >= 1) {
      setState(() => _everyNDays = n);
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _everyNStart,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _everyNStart = picked);
    }
  }

  String _weekdayShort(int n) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    if (n < 1 || n > 7) return '?';
    return '周${names[n - 1]}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}

/// 小节标题
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(label, style: AppText.caption(color: pp.inkMuted)),
    );
  }
}

/// 纸张风格输入框（去 Material 默认灰底 + 圆角塑料感）
class _PaperField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;

  const _PaperField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: AppText.caption(color: pp.inkMuted)),
          ),
          TextField(
            controller: controller,
            maxLines: maxLines,
            cursorColor: pp.accent,
            style: AppText.body(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.body(color: pp.inkFaint),
              filled: true,
              // §0.1：输入框 fillColor 用 bgCard 浅主题色。
              fillColor: pp.bgCard,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: pp.line, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: pp.line, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: pp.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}