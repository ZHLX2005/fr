import 'package:flutter/material.dart';
import '../../../widgets/context_colors.dart';
import 'zen_theme.dart';

/// Zen 主题日历日期选择器 —— 替代系统 [showDatePicker] 的 Material 亮色弹窗。
///
/// 月历网格 + 上下月切换，颜色全部来自 [ZenColors]：
/// surface 底 / hair 边框 / sage 选中 / secondary 星期表头与非当月日。
///
/// 用法与 showDatePicker 对齐：
/// ```dart
/// final picked = await showZenDatePicker(
///   context: context,
///   initialDate: DateTime.now(),
///   firstDate: DateTime(2020),
///   lastDate: DateTime(2035),
///   title: '开播日期',
/// );
/// ```
Future<DateTime?> showZenDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _ZenDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _ZenDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  const _ZenDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_ZenDatePickerDialog> createState() => _ZenDatePickerDialogState();
}

class _ZenDatePickerDialogState extends State<_ZenDatePickerDialog> {
  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  late DateTime _month; // 当前展示月（任意日）
  late DateTime _selected; // 已选中日

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _month = DateTime(_selected.year, _selected.month);
  }

  bool _canGoPrev(DateTime month) => DateTime(month.year, month.month).isAfter(
        DateTime(widget.firstDate.year, widget.firstDate.month),
      );

  bool _canGoNext(DateTime month) {
    final next = DateTime(month.year, month.month + 1);
    final last = DateTime(widget.lastDate.year, widget.lastDate.month);
    return !next.isAfter(last);
  }

  bool _inRange(DateTime day) =>
      !day.isBefore(DateTime(
        widget.firstDate.year,
        widget.firstDate.month,
        widget.firstDate.day,
      )) &&
      !day.isAfter(DateTime(
        widget.lastDate.year,
        widget.lastDate.month,
        widget.lastDate.day,
      ));

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    return Dialog(
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.colors.outline),
      ),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 + 月份切换
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: ZenText.title),
                ),
                _monthNavButton(
                  icon: Icons.chevron_left,
                  enabled: _canGoPrev(_month),
                  onTap: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    '${_month.year}年${_month.month}月',
                    textAlign: TextAlign.center,
                    style: ZenText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                _monthNavButton(
                  icon: Icons.chevron_right,
                  enabled: _canGoNext(_month),
                  onTap: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            // 星期表头
            Row(
              children: [
                for (final w in _weekdayNames)
                  Expanded(
                    child: Center(
                      child: Text(w, style: ZenText.label.copyWith(fontSize: 12)),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 6),
            // 日网格
            _buildGrid(todayKey),
            SizedBox(height: 12),
            // 底部操作
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: ZenText.button.copyWith(color: context.colors.textMuted)),
                ),
                SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: Text('确定', style: ZenText.button.copyWith(color: context.colors.accent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: CircleBorder(),
      child: Opacity(
        opacity: enabled ? 1 : 0.25,
        child: Icon(icon, size: 22, color: context.colors.textMuted),
      ),
    );
  }

  Widget _buildGrid(DateTime todayKey) {
    // 当月第一天所在周的一（可能含上月末几天）
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final leading = firstOfMonth.weekday - 1; // 1=周一
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      cells.add(_buildDayCell(date, date == todayKey));
    }
    // 补齐到 6 行 × 7 列，保证网格高度稳定
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    return Column(
      children: [
        for (var r = 0; r < cells.length ~/ 7; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: cells[r * 7 + c]),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell(DateTime date, bool isToday) {
    final isSelected = date == DateTime(_selected.year, _selected.month, _selected.day);
    final enabled = _inRange(date);
    final isWeekend = date.weekday >= 6;

    return InkWell(
      onTap: enabled
          ? () => setState(() => _selected = date)
          : null,
      customBorder: CircleBorder(),
      child: Opacity(
        opacity: enabled ? 1 : 0.3,
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? context.colors.accent : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
            border: Border.all(
              color: isToday && !isSelected ? context.colors.danger : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
            ),
          ),
          child: Text(
            '${date.day}',
            style: ZenText.body.copyWith(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              color: isSelected
                  ? Theme.of(context).colorScheme.surface
                  : (isWeekend ? context.colors.danger : context.colors.text),
            ),
          ),
        ),
      ),
    );
  }
}
