import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import '../domain/calendar_task.dart';
import 'calendar_palette.dart';

/// 添加任务底部表单。返回 null 表示取消。
Future<CalendarTaskDraft?> showCalendarTaskSheet(
  BuildContext context, {
  required CalendarPalette palette,
  required DateTime initialDate,
}) async {
  final titleController = TextEditingController();
  final notesController = TextEditingController();
  var allDay = false;
  var date = calendarDateOnly(initialDate);
  var time = TimeOfDay.now();

  try {
    final result = await showModalBottomSheet<CalendarTaskDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final canSave = titleController.text.trim().isNotEmpty;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
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
                          hintStyle: TextStyle(color: palette.textSecondary),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          counterText: '',
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      Divider(color: palette.divider),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetaChip(
                            icon: Icons.calendar_today_outlined,
                            label: '${date.year}年${date.month}月${date.day}日',
                            palette: palette,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
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
                              label: time.format(context),
                              palette: palette,
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: time,
                                );
                                if (picked != null) {
                                  setSheetState(() => time = picked);
                                }
                              },
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          '全天任务',
                          style: TextStyle(
                            fontSize: 14,
                            color: palette.textPrimary,
                          ),
                        ),
                        value: allDay,
                        activeThumbColor: palette.accent,
                        onChanged: (value) {
                          setSheetState(() => allDay = value);
                        },
                      ),
                      TextField(
                        controller: notesController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: '备注（可选）',
                          hintStyle: TextStyle(color: palette.textSecondary),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: canSave
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
                                          : start.add(const Duration(hours: 1)),
                                      allDay: allDay,
                                    ),
                                  );
                                }
                              : null,
                          child: const Text('添加任务'),
                        ),
                      ),
                    ],
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
    return Material(
      color: palette.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
      ),
    );
  }
}
