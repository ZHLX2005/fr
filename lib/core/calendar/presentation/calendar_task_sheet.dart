import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import '../domain/calendar_task.dart';
import 'calendar_controls.dart';
import 'calendar_palette.dart';
import 'calendar_pickers.dart';

/// 添加任务底部表单。返回 null 表示取消。
Future<CalendarTaskDraft?> showCalendarTaskSheet(
  BuildContext context, {
  required CalendarPalette palette,
  required DateTime initialDate,
  TimeOfDay? initialTime,
}) async {
  final titleController = TextEditingController();
  final notesController = TextEditingController();
  var allDay = false;
  var date = calendarDateOnly(initialDate);
  var time = initialTime ?? TimeOfDay.now();

  try {
    final result = await showModalBottomSheet<CalendarTaskDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final canSave = titleController.text.trim().isNotEmpty;

            return Container(
              decoration: BoxDecoration(
                color: palette.overlay,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: palette.divider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: titleController,
                          autofocus: true,
                          onChanged: (_) => setSheetState(() {}),
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: '要做什么？',
                            hintStyle: TextStyle(
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                          ),
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                          cursorColor: palette.accent,
                        ),
                        Divider(color: palette.divider),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaChip(
                              icon: Icons.calendar_today_outlined,
                              label:
                                  '${date.year}年${date.month}月${date.day}日',
                              palette: palette,
                              onTap: () async {
                                final picked = await showCalendarDatePicker(
                                  context,
                                  palette: palette,
                                  initialDate: date,
                                );
                                if (picked != null) {
                                  setSheetState(() {
                                    date = calendarDateOnly(picked);
                                  });
                                }
                              },
                            ),
                            if (!allDay)
                              _MetaChip(
                                icon: Icons.schedule,
                                label:
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                palette: palette,
                                onTap: () async {
                                  final picked = await showCalendarTimePicker(
                                    context,
                                    palette: palette,
                                    initialTime: time,
                                  );
                                  if (picked != null) {
                                    setSheetState(() => time = picked);
                                  }
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.wb_sunny_outlined,
                              size: 19,
                              color: palette.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '全天任务',
                              style: TextStyle(
                                fontSize: 14,
                                color: palette.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            CalendarSwitch(
                              value: allDay,
                              palette: palette,
                              onChanged: (value) {
                                setSheetState(() => allDay = value);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: notesController,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: '备注（可选）',
                            hintStyle: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: palette.textPrimary,
                          ),
                          cursorColor: palette.accent,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: CalendarActionButton(
                            label: '添加任务',
                            palette: palette,
                            onTap: canSave
                                ? () {
                                    final start = allDay
                                        ? calendarDayStart(date)
                                        : DateTime(
                                            date.year,
                                            date.month,
                                            date.day,
                                            time.hour,
                                            time.minute,
                                          );
                                    Navigator.of(sheetContext).pop(
                                      CalendarTaskDraft(
                                        title: titleController.text.trim(),
                                        notes: notesController.text,
                                        start: start,
                                        end: allDay
                                            ? start.add(const Duration(days: 1))
                                            : start.add(
                                                const Duration(hours: 1),
                                              ),
                                        allDay: allDay,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return result;
  } finally {
    titleController.dispose();
    notesController.dispose();
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: palette.divider.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: palette.accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: palette.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
