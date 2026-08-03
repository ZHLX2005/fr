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
  bool _isLeap = false; // 仅农历：该月是否闰月
  String? _lunarPreview; // 当前历法的对方历法等值预览
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

    // 回显已有生日事件：直接读存值（year/month/day 已是该 system 历法下的值），
    // 不做任何换算 —— 之前的 lunarFromSolar 二次换算就是漂移 bug 的源头。
    if (p != null) {
      final existing = widget.cal.events.firstWhere(
        (e) => e.personId == p.id && e.type == EventType.birthday,
        orElse: () => _sentinel(),
      );
      if (existing.id != '_empty_') {
        _system = existing.system;
        _isLeap = existing.isLeap;
        _date.text =
            '${existing.year.toString().padLeft(4, '0')}'
            '${existing.month.toString().padLeft(2, '0')}'
            '${existing.day.toString().padLeft(2, '0')}';
      }
    }
    // 首帧后刷新预览
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateLunarPreview(_date.text);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 8 位数字 + 当前历法 → 对方历法等值预览（年取自输入本身）
  void _updateLunarPreview(String text) {
    if (text.length != 8 || int.tryParse(text) == null) {
      setState(() => _lunarPreview = null);
      return;
    }
    try {
      final ymd = int.parse(text);
      if (_system == CalendarSystem.solar) {
        // 公历输入 → 预览农历
        final solar = _codec.parseSolarFromYmd8(ymd);
        final l = _codec.lunarFromSolar(solar);
        setState(() {
          _lunarPreview = '${l.year} 年 ${l.isLeap ? "闰" : ""}${l.month} 月 ${l.day} 日';
        });
      } else {
        // 农历输入 → 预览公历（年来自输入）
        final solar = _codec.parseLunarFromYmd8(ymd, isLeap: _isLeap);
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
      final y = ymd ~/ 10000;
      final m = (ymd ~/ 100) % 100;
      final d = ymd % 100;
      // 删除旧 birthday 事件（如果有）
      final oldBirthday = cal.events.firstWhere(
        (e) => e.personId == saved.id && e.type == EventType.birthday,
        orElse: () => _sentinel(),
      );
      if (oldBirthday.id != '_empty_') {
        await cal.remove(oldBirthday.id);
      }
      // SoT：存的就是用户输入的原值（year/month/day 已是该 system 历法下的值）。
      // solar → yearly（公历月日固定）；lunar → yearlyLunarAuto + 锚年。
      if (_system == CalendarSystem.solar) {
        await cal.add(
          type: EventType.birthday,
          title: '${saved.name}生日',
          system: CalendarSystem.solar,
          year: y,
          month: m,
          day: d,
          recurrence: Recurrence.yearly,
          colorTag: ColorTag.amber,
          personId: saved.id,
        );
      } else {
        await cal.add(
          type: EventType.birthday,
          title: '${saved.name}生日',
          system: CalendarSystem.lunar,
          year: y,
          month: m,
          day: d,
          isLeap: _isLeap,
          recurrence: Recurrence.yearlyLunarAuto,
          colorTag: ColorTag.amber,
          personId: saved.id,
          lunarAnchorYear: y,
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
                final text = _date.text;
                // 切换历法：若当前已是合法 8 位日期，把字段值换算成对方历法的等值，
                // 而不是"用同一串数字在新历法下重新解释"。
                if (text.length == 8 &&
                    int.tryParse(text) != null &&
                    v != _system) {
                  try {
                    final r = _codec.convertSystem(
                      int.parse(text),
                      from: _system,
                      to: v,
                      sourceIsLeap: _isLeap,
                    );
                    _date.text = r.ymd8.toString().padLeft(8, '0');
                    _isLeap = r.isLeap;
                  } catch (_) {
                    // 换算失败（如非法农历日）：仅切 system，保留原值由用户改
                  }
                }
                _system = v;
                _updateLunarPreview(_date.text);
              });
            },
            displayName: (s) => s == CalendarSystem.solar ? '公历' : '农历',
          ),
          // 仅农历可见：是否闰月
          if (_system == CalendarSystem.lunar)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Checkbox(
                    value: _isLeap,
                    onChanged: (v) {
                      setState(() {
                        _isLeap = v ?? false;
                        _updateLunarPreview(_date.text);
                      });
                    },
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isLeap = !_isLeap;
                        _updateLunarPreview(_date.text);
                      });
                    },
                    child: Text(
                      '闰月',
                      style: AppText.body(color: PaperPalette.ink),
                    ),
                  ),
                ],
              ),
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
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: PaperPalette.accent,
              backgroundColor: PaperPalette.bgElevated,
              side: BorderSide(
                color: PaperPalette.accent.withValues(alpha: 0.5),
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