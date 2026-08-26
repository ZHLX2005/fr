import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/native/home_widget/calendar_widget_data.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event_occurrence.dart';

void main() {
  Event mk() => Event(
        id: 'e1',
        title: 't',
        type: EventType.task,
        anchor: const SolarAnchor(month: 8, day: 15, year: 2025),
        period: PeriodFactory.yearly(),
        colorTag: ColorTag.gray,
        groupId: 'default',
        createdAt: DateTime(2025, 1, 1),
      );

  test('fromOccurrences groups by day-of-month', () {
    final e = mk();
    final occ = [
      EventOccurrence(event: e, date: DateTime(2025, 8, 15)),
    ];
    final data = CalendarWidgetData.fromOccurrences(
      year: 2025,
      month: 8,
      occurrences: occ,
    );
    expect(data.colorsByDay['15'], isNotNull);
    expect(data.colorsByDay['15']!.length, 1);
  });

  test('occurrences outside the month are dropped', () {
    final e = mk();
    final occ = [
      EventOccurrence(event: e, date: DateTime(2025, 7, 15)),
      EventOccurrence(event: e, date: DateTime(2025, 8, 15)),
    ];
    final data = CalendarWidgetData.fromOccurrences(
      year: 2025,
      month: 8,
      occurrences: occ,
    );
    expect(data.colorsByDay.containsKey('15'), true);
    expect(data.colorsByDay['15']!.length, 1);
  });
}