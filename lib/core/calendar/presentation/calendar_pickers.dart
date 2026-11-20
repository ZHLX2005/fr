import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import 'calendar_controls.dart';
import 'calendar_grid.dart';
import 'calendar_palette.dart';

const _kMonthNames = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];

Future<DateTime?> showCalendarDatePicker(
  BuildContext context, {
  required CalendarPalette palette,
  required DateTime initialDate,
}) {
  var selected = calendarDateOnly(initialDate);
  var visibleMonth = DateTime(selected.year, selected.month, 1);

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        CalendarIconButton(
                          icon: Icons.chevron_left,
                          palette: palette,
                          size: 36,
                          iconSize: 20,
                          onTap: () {
                            setSheetState(() {
                              visibleMonth = DateTime(
                                visibleMonth.year,
                                visibleMonth.month - 1,
                                1,
                              );
                            });
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '${visibleMonth.year}年 ${_kMonthNames[visibleMonth.month - 1]}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        CalendarIconButton(
                          icon: Icons.chevron_right,
                          palette: palette,
                          size: 36,
                          iconSize: 20,
                          onTap: () {
                            setSheetState(() {
                              visibleMonth = DateTime(
                                visibleMonth.year,
                                visibleMonth.month + 1,
                                1,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CalendarMonthGrid(
                      month: visibleMonth,
                      selectedDate: selected,
                      markedDates: const {},
                      mondayFirst: true,
                      palette: palette,
                      showHolidays: false,
                      onSelected: (date) {
                        setSheetState(() {
                          selected = calendarDateOnly(date);
                          visibleMonth = DateTime(date.year, date.month, 1);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CalendarActionButton(
                        label:
                            '选择 ${selected.year}年${selected.month}月${selected.day}日',
                        palette: palette,
                        onTap: () => Navigator.of(sheetContext).pop(selected),
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
}

Future<TimeOfDay?> showCalendarTimePicker(
  BuildContext context, {
  required CalendarPalette palette,
  required TimeOfDay initialTime,
}) {
  var hour = initialTime.hour;
  var minute = initialTime.minute;
  final hourController = FixedExtentScrollController(initialItem: hour);
  final minuteController = FixedExtentScrollController(initialItem: minute);

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: palette.overlay,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '选择时间',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: Row(
                        children: [
                          Expanded(
                            child: _WheelColumn(
                              controller: hourController,
                              count: 24,
                              selected: hour,
                              palette: palette,
                              onSelected: (value) {
                                setSheetState(() => hour = value);
                              },
                            ),
                          ),
                          Text(
                            ':',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          Expanded(
                            child: _WheelColumn(
                              controller: minuteController,
                              count: 60,
                              selected: minute,
                              palette: palette,
                              onSelected: (value) {
                                setSheetState(() => minute = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: CalendarActionButton(
                        label:
                            '确定 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                        palette: palette,
                        onTap: () => Navigator.of(sheetContext)
                            .pop(TimeOfDay(hour: hour, minute: minute)),
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
  ).whenComplete(() {
    hourController.dispose();
    minuteController.dispose();
  });
}

class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.count,
    required this.selected,
    required this.palette,
    required this.onSelected,
  });

  final FixedExtentScrollController controller;
  final int count;
  final int selected;
  final CalendarPalette palette;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      diameterRatio: 1.4,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          final active = index == selected;
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: active ? palette.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                index.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? palette.accent : palette.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
