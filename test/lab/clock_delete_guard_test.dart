import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock_record.dart';

void main() {
  group('LabClockRecord.canDelete', () {
    test('已完成的记录可删', () {
      final r = LabClockRecord(
        id: 'a',
        clockId: 'c',
        clockTitle: 't',
        startTime: DateTime(2026),
        durationSeconds: 60,
        endTime: DateTime(2026),
        completed: true,
      );
      expect(r.canDelete, isTrue);
    });

    test('运行中/暂停（未完成）的记录不可删', () {
      final r = LabClockRecord(
        id: 'a',
        clockId: 'c',
        clockTitle: 't',
        startTime: DateTime(2026),
        durationSeconds: 60,
      );
      expect(r.canDelete, isFalse);
    });

    test('提前结算未完成的记录不可删', () {
      final r = LabClockRecord(
        id: 'a',
        clockId: 'c',
        clockTitle: 't',
        startTime: DateTime(2026),
        durationSeconds: 60,
        endTime: DateTime(2026),
        completed: false,
      );
      expect(r.canDelete, isFalse);
    });
  });
}
