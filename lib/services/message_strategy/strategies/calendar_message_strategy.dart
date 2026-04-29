import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../interfaces/interfaces.dart';
import '../data/calendar_message_data.dart';

/// 日历消息组件（保留日期范围选择交互）
class _CalendarMessageWidget extends StatefulWidget {
  const _CalendarMessageWidget();

  @override
  State<_CalendarMessageWidget> createState() => _CalendarMessageWidgetState();
}

class _CalendarMessageWidgetState extends State<_CalendarMessageWidget> {
  List<DateTime> dateList = <DateTime>[];
  DateTime currentMonthDate = DateTime.now();
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    setListOfDate(currentMonthDate);
  }

  void setListOfDate(DateTime monthDate) {
    dateList.clear();
    final DateTime newDate = DateTime(monthDate.year, monthDate.month, 0);
    int previousMothDay = 0;
    if (newDate.weekday < 7) {
      previousMothDay = newDate.weekday;
      for (int i = 1; i <= previousMothDay; i++) {
        dateList.add(newDate.subtract(Duration(days: previousMothDay - i)));
      }
    }
    for (int i = 0; i < (42 - previousMothDay); i++) {
      dateList.add(newDate.add(Duration(days: i + 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 显示选中的日期范围
          if (startDate != null || endDate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (startDate != null)
                    Text(
                      DateFormat('yyyy-MM-dd').format(startDate!),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                  if (startDate != null && endDate != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('→', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    ),
                  if (endDate != null)
                    Text(
                      DateFormat('yyyy-MM-dd').format(endDate!),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          // 月份导航
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: () {
                  setState(() {
                    currentMonthDate = DateTime(currentMonthDate.year, currentMonthDate.month, 0);
                    setListOfDate(currentMonthDate);
                  });
                },
              ),
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat('MMMM, yyyy').format(currentMonthDate),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () {
                  setState(() {
                    currentMonthDate = DateTime(currentMonthDate.year, currentMonthDate.month + 2, 0);
                    setListOfDate(currentMonthDate);
                  });
                },
              ),
            ],
          ),
          // 星期名称
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: getDaysNameUI()),
          ),
          const SizedBox(height: 4),
          // 日期网格
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: getDaysNoUI()),
          ),
        ],
      ),
    );
  }

  List<Widget> getDaysNameUI() {
    final colorScheme = Theme.of(context).colorScheme;
    return List.generate(7, (i) {
      return Expanded(
        child: Center(
          child: Text(
            ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.primary),
          ),
        ),
      );
    });
  }

  List<Widget> getDaysNoUI() {
    final colorScheme = Theme.of(context).colorScheme;
    List<Widget> noList = [];
    int count = 0;
    for (int i = 0; i < dateList.length / 7; i++) {
      List<Widget> listUI = [];
      for (int j = 0; j < 7; j++) {
        final DateTime date = dateList[count];
        listUI.add(
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                  // 范围背景
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2, left: 2, right: 2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: startDate != null && endDate != null &&
                                  (getIsItStartAndEndDate(date) || getIsInRange(date))
                              ? colorScheme.primary.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.horizontal(
                            left: isStartDateRadius(date) ? const Radius.circular(16) : Radius.zero,
                            right: isEndDateRadius(date) ? const Radius.circular(16) : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 日期点击
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => onDateClick(date),
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: getIsItStartAndEndDate(date) ? colorScheme.primary : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: getIsItStartAndEndDate(date)
                                      ? colorScheme.onPrimary
                                      : currentMonthDate.month == date.month
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface.withValues(alpha: 0.3),
                                  fontWeight: getIsItStartAndEndDate(date) ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 今日标记
                  if (DateTime.now().day == date.day &&
                      DateTime.now().month == date.month &&
                      DateTime.now().year == date.year)
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          height: 4,
                          width: 4,
                          decoration: BoxDecoration(
                            color: getIsInRange(date) ? colorScheme.onPrimary : colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        count++;
      }
      noList.add(Row(children: listUI));
    }
    return noList;
  }

  bool getIsInRange(DateTime date) {
    if (startDate != null && endDate != null) {
      return date.isAfter(startDate!) && date.isBefore(endDate!);
    }
    return false;
  }

  bool getIsItStartAndEndDate(DateTime date) {
    if (startDate != null && startDate!.day == date.day && startDate!.month == date.month && startDate!.year == date.year) return true;
    if (endDate != null && endDate!.day == date.day && endDate!.month == date.month && endDate!.year == date.year) return true;
    return false;
  }

  bool isStartDateRadius(DateTime date) {
    if (startDate != null && startDate!.day == date.day && startDate!.month == date.month) return true;
    if (date.weekday == 1) return true;
    return false;
  }

  bool isEndDateRadius(DateTime date) {
    if (endDate != null && endDate!.day == date.day && endDate!.month == date.month) return true;
    if (date.weekday == 7) return true;
    return false;
  }

  void onDateClick(DateTime date) {
    if (currentMonthDate.month != date.month) return;
    if (startDate == null) {
      startDate = date;
    } else if (startDate != date && endDate == null) {
      endDate = date;
    } else if (startDate!.day == date.day && startDate!.month == date.month) {
      startDate = null;
    } else if (endDate != null && endDate!.day == date.day && endDate!.month == date.month) {
      endDate = null;
    }
    if (startDate == null && endDate != null) {
      startDate = endDate;
      endDate = null;
    }
    if (startDate != null && endDate != null && !endDate!.isAfter(startDate!)) {
      final d = startDate!;
      startDate = endDate;
      endDate = d;
    }
    setState(() {});
  }
}

/// Strategy for rendering calendar messages
class CalendarMessageWidgetStrategy extends MessageWidgetStrategy<CalendarMessageData> {
  @override
  Widget build(BuildContext context, CalendarMessageData data) {
    return const _CalendarMessageWidget();
  }

  @override
  CalendarMessageData createMockData() => CalendarMessageData(
    startDate: DateTime.now(),
    endDate: DateTime.now().add(const Duration(days: 3)),
  );
}
