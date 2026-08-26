import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/calendar_config.dart';
import '../data/event_draft.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/anchor.dart';
import '../domain/event.dart';
import '../domain/event_occurrence.dart';
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
  late bool _repeatYearly;
  late CalendarSystem _system;
  String? _personName;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? EventType.task;
    _color = e?.colorTag ?? ColorTag.gray;
    _repeatYearly = e?.period is YearlyPeriod;
    _system = e?.anchor is LunarAnchor ? CalendarSystem.lunar : CalendarSystem.solar;
    _personName = (e?.people.isNotEmpty ?? false) ? e!.people.first.name : null;
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
    // Build anchor from current widget.date + selected system.
    final anchor = _system == CalendarSystem.lunar
        ? AnchorFactory.lunar(
            month: widget.date.month,
            day: widget.date.day,
            isLeap: false,
            year: widget.date.year,
          )
        : AnchorFactory.solar(
            month: widget.date.month,
            day: widget.date.day,
            year: widget.date.year,
          );
    final period = _repeatYearly
        ? PeriodFactory.yearly()
        : PeriodFactory.oneShot();
    final people = <PersonPatch>[];
    if (_personName != null && _personName!.isNotEmpty) {
      // patch relation 取当前 roster 里的（如有），保持向后兼容
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
          // 日期 header：同时显示公历与农历
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
          ChipChoice<bool>(
            label: '重复',
            values: const [false, true],
            selected: _repeatYearly,
            onChanged: (v) => setState(() => _repeatYearly = v),
            displayName: (v) => v ? '每年' : '仅一次',
          ),
          ChipChoice<CalendarSystem>(
            label: '历法',
            values: CalendarSystem.values.toList(),
            selected: _system,
            onChanged: (v) => setState(() => _system = v),
            displayName: (s) => s == CalendarSystem.solar ? '公历' : '农历',
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