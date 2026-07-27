import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/lunar_date_codec.dart';
import '../domain/person.dart';
import '../domain/recurrence.dart';
import '../lunar_adapter.dart';
import 'widgets/chip_choice.dart';
import 'widgets/paper_button.dart';

/// 新增/编辑人（输入 8 位数字生日 → 自动建 birthday 事件）
class PersonFormSheet extends StatefulWidget {
  final Person? existing;
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  const PersonFormSheet({
    super.key,
    required this.cal,
    required this.people,
    this.existing,
  });

  @override
  State<PersonFormSheet> createState() => _PersonFormSheetState();
}

class _PersonFormSheetState extends State<PersonFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _date;
  late final TextEditingController _note;
  late PersonRelation _relation;
  late CalendarSystem _system;
  String? _lunarPreview; // 8 位数字 → 实时反推的农历预览
  final _codec = LunarDateCodec(LunarAdapter());

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _date = TextEditingController();
    _note = TextEditingController(text: p?.note ?? '');
    _relation = p?.relation ?? PersonRelation.family;
    _system = CalendarSystem.solar;

    // 回显已有生日事件：找到该人第一个 birthday 事件，反推 8 位数字与历法
    if (p != null) {
      final existing = widget.cal.events.firstWhere(
        (e) => e.personId == p.id && e.type == EventType.birthday,
        orElse: () => _sentinel(),
      );
      if (existing.id != '_empty_') {
        _system = existing.system;
        if (existing.system == CalendarSystem.solar) {
          _date.text = _codec
              .toYmd8(
                DateTime(existing.year, existing.month, existing.day),
                CalendarSystem.solar,
              )
              .toString();
        } else {
          // 农历：从公历月日反推农历月日，拼接当年
          final l = _codec.lunarFromSolar(
            DateTime(existing.year, existing.month, existing.day),
          );
          _date.text =
              '${l.year.toString().padLeft(4, '0')}${l.month.toString().padLeft(2, '0')}${l.day.toString().padLeft(2, '0')}';
        }
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 8 位数字 + 当前历法 → 对方历法预览
  void _updateLunarPreview(String text) {
    if (text.length != 8 || int.tryParse(text) == null) {
      setState(() => _lunarPreview = null);
      return;
    }
    try {
      if (_system == CalendarSystem.solar) {
        // 输入公历 → 预览农历
        final solar = _codec.parseSolarFromYmd8(int.parse(text));
        final l = _codec.lunarFromSolar(solar);
        setState(() {
          _lunarPreview = '${l.year} 年 ${l.isLeap ? "闰" : ""}${l.month} 月 ${l.day} 日';
        });
      } else {
        // 输入农历 → 预览公历
        final solar = _codec.parseLunarFromYmd8(int.parse(text), year: DateTime.now().year);
        setState(() {
          _lunarPreview = '${solar.year} 年 ${solar.month} 月 ${solar.day} 日';
        });
      }
    } catch (_) {
      setState(() => _lunarPreview = null);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _date.text.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写姓名与 8 位数字生日')),
      );
      return;
    }
    final ymd = int.parse(_date.text);
    final people = widget.people;
    final cal = widget.cal;
    final saved = widget.existing ??
        await people.add(
          name: _name.text,
          relation: _relation,
          avatarEmoji: null,
          note: _note.text.isEmpty ? null : _note.text,
        );
    if (!mounted) return;

    try {
      final solar = _system == CalendarSystem.solar
          ? _codec.parseSolarFromYmd8(ymd)
          : _codec.parseLunarFromYmd8(ymd, year: DateTime.now().year);
      // 删除旧 birthday 事件（如果有）
      final oldBirthday = cal.events.firstWhere(
        (e) => e.personId == saved.id && e.type == EventType.birthday,
        orElse: () => _sentinel(),
      );
      if (oldBirthday.id != '_empty_') {
        await cal.remove(oldBirthday.id);
      }
      // 建新 birthday 事件
      if (_system == CalendarSystem.solar) {
        // 按公历过：直接用公历月日 + yearly
        await cal.add(
          type: EventType.birthday,
          title: '${saved.name}生日',
          system: CalendarSystem.solar,
          month: solar.month,
          day: solar.day,
          recurrence: Recurrence.yearly,
          colorTag: ColorTag.amber,
          personId: saved.id,
        );
      } else {
        // 按农历过：把公历 birth 反推为农历月日，存农历月日 + yearlyLunarAuto + 锚定年
        final l = _codec.lunarFromSolar(solar);
        await cal.add(
          type: EventType.birthday,
          title: '${saved.name}生日',
          system: CalendarSystem.lunar,
          month: l.month,
          day: l.day,
          recurrence: Recurrence.yearlyLunarAuto,
          colorTag: ColorTag.amber,
          personId: saved.id,
          lunarAnchorYear: l.year,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('日期解析失败：$e')),
        );
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Event _sentinel() => Event(
        id: '_empty_',
        type: EventType.birthday,
        title: '',
        system: CalendarSystem.solar,
        year: 0,
        month: 0,
        day: 0,
        recurrence: Recurrence.none,
        colorTag: ColorTag.gray,
        createdAt: DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaperPalette.bg,
      appBar: AppBar(
        backgroundColor: PaperPalette.bg,
        elevation: 0,
        title: Text(widget.existing == null ? '新增人' : '编辑人', style: AppText.title()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 边框强调：当前操作的人卡片
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PaperPalette.bgElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PaperPalette.accent, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing?.name ?? '新增',
                  style: AppText.title(),
                ),
                if (widget.existing != null) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.existing!.relation.name,
                    style: AppText.caption(),
                  ),
                ),
              ],
            ),
          ),
          _PaperField(controller: _name, label: '姓名', hint: '姓名/昵称'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PaperField(
                controller: _date,
                label: '生日 8 位数字',
                hint: 'YYYYMMDD',
                keyboardType: TextInputType.number,
                onChanged: _updateLunarPreview,
              ),
              if (_lunarPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    _system == CalendarSystem.solar
                        ? '≈ 农历 $_lunarPreview'
                        : '≈ 公历 $_lunarPreview',
                    style: AppText.caption(color: PaperPalette.accent),
                  ),
                ),
            ],
          ),
          ChipChoice<CalendarSystem>(
            label: '历法',
            values: CalendarSystem.values.toList(),
            selected: _system,
            onChanged: (v) {
              setState(() {
                _system = v;
                _updateLunarPreview(_date.text);
              });
            },
            displayName: (s) => s == CalendarSystem.solar ? '公历' : '农历',
          ),
          ChipChoice<PersonRelation>(
            label: '关系',
            values: PersonRelation.values.toList(),
            selected: _relation,
            onChanged: (v) => setState(() => _relation = v),
            displayName: _relationName,
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

  String _relationName(PersonRelation r) {
    switch (r) {
      case PersonRelation.self:
        return '自己';
      case PersonRelation.family:
        return '家人';
      case PersonRelation.friend:
        return '朋友';
      case PersonRelation.colleague:
        return '同事';
      case PersonRelation.other:
        return '其他';
    }
  }
}

/// 纸张风格输入框
class _PaperField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _PaperField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
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
            keyboardType: keyboardType,
            onChanged: onChanged,
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