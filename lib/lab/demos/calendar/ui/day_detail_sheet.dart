import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/recurrence.dart';
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
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final events = cal.eventsOnDate(date);

        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 16,
          ),
          decoration: const BoxDecoration(
            color: PaperPalette.bgElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                    color: PaperPalette.inkMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: PaperPalette.line),
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('暂无事件',
                      style: AppText.body(color: PaperPalette.inkMuted)),
                )
              else
                ...events.map(
                  (e) => _EventRow(
                    event: e,
                    cal: cal,
                    people: people,
                    personName: e.personId == null
                        ? null
                        : people.byId(e.personId!)?.name,
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
    final color = _hexToColor(event.colorTag.hex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => EventFormSheet(
              date: DateTime(event.year, event.month, event.day),
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
                        event.system == CalendarSystem.solar ? '公历' : '农历',
                        if (personName != null) personName!,
                      ].join(' · '),
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              if (event.systemCalendarEventId != null)
                const Icon(Icons.cloud_done_outlined,
                    size: 14, color: PaperPalette.inkMuted),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: PaperPalette.inkMuted,
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PaperPalette.bgElevated,
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
            style: TextButton.styleFrom(foregroundColor: PaperPalette.today),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await cal.remove(event.id);
      if (context.mounted) Navigator.pop(context);
    }
  }

  Color _hexToColor(String hex) {
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    final v = int.tryParse(s, radix: 16) ?? 0;
    return Color(0xFF000000 | v);
  }
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
  late Recurrence _rec;
  late CalendarSystem _system;
  String? _personId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? EventType.task;
    _color = e?.colorTag ?? ColorTag.gray;
    _rec = e?.recurrence ?? Recurrence.none;
    _system = e?.system ?? CalendarSystem.solar;
    _personId = e?.personId;
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
    if (widget.existing != null) {
      await cal.update(widget.existing!.copyWith(
        title: _title.text,
        type: _type,
        colorTag: _color,
        recurrence: _rec,
        system: _system,
        personId: _personId,
        note: _note.text.isEmpty ? null : _note.text,
      ));
    } else {
      await cal.add(
        type: _type,
        title: _title.text,
        system: _system,
        month: widget.date.month,
        day: widget.date.day,
        recurrence: _rec,
        colorTag: _color,
        personId: _personId,
        note: _note.text.isEmpty ? null : _note.text,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaperPalette.bg,
      appBar: AppBar(
        backgroundColor: PaperPalette.bg,
        elevation: 0,
        title: Text(widget.existing == null ? '新建事件' : '编辑事件', style: AppText.title()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 日期 header：同时显示公历与农历
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: PaperPalette.line, width: 1)),
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
            values: [null, ...widget.people.people.map((p) => p.id)],
            selected: _personId,
            onChanged: (v) => setState(() => _personId = v),
            displayName: (v) {
              if (v == null) return '不关联';
              final p = widget.people.byId(v);
              return p == null ? '已删除' : p.name;
            },
          ),
          ChipChoice<Recurrence>(
            label: '重复',
            values: const [Recurrence.none, Recurrence.yearly],
            selected: _rec == Recurrence.manual ? Recurrence.yearly : _rec,
            onChanged: (v) => setState(() => _rec = v),
            displayName: _recName,
          ),
          ChipChoice<CalendarSystem>(
            label: '历法',
            values: CalendarSystem.values.toList(),
            selected: _system,
            onChanged: (v) => setState(() {
              _system = v;
              _rec = _recFor(_system, _rec);
            }),
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
          PaperPrimaryButton(
            label: '保存',
            onPressed: _save,
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

  String _recName(Recurrence r) {
    switch (r) {
      case Recurrence.none:
        return '仅一次';
      case Recurrence.yearly:
        return '每年公历';
      case Recurrence.yearlyLunarAuto:
        return '每年农历';
      case Recurrence.manual:
        return '手动';
    }
  }

  /// 重复项联动：根据历法决定可选重复项
  /// - 公历：仅一次 / 每年公历 / 手动
  /// - 农历：仅一次 / 每年农历
  List<Recurrence> _availableRecurrences() {
    return _system == CalendarSystem.solar
        ? [Recurrence.none, Recurrence.yearly, Recurrence.manual]
        : [Recurrence.none, Recurrence.yearlyLunarAuto];
  }

  /// 历法切换时，把当前重复值映射到新历法下的合法值
  Recurrence _recFor(CalendarSystem sys, Recurrence current) {
    if (sys == CalendarSystem.solar) {
      if (current == Recurrence.yearlyLunarAuto) return Recurrence.yearly;
      return current;
    } else {
      if (current == Recurrence.yearly) return Recurrence.yearlyLunarAuto;
      if (current == Recurrence.manual) return Recurrence.none;
      return current;
    }
  }

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: AppText.caption(color: PaperPalette.inkMuted)),
          ),
          TextField(
            controller: controller,
            maxLines: maxLines,
            cursorColor: PaperPalette.accent,
            style: AppText.body(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.body(color: PaperPalette.inkFaint),
              filled: true,
              fillColor: PaperPalette.bgElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaperPalette.line, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaperPalette.line, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: PaperPalette.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}