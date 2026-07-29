import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/focus/models/focus_session.dart';

void main() {
  group('FocusSession roundtrip (subjectId removed)', () {
    final session = FocusSession(
      id: 'abc',
      durationMinutes: 25,
      startTime: DateTime.utc(2026, 7, 29, 10),
      endTime: DateTime.utc(2026, 7, 29, 10, 25),
      mode: FocusMode.freeTime,
      note: 'n',
    );

    test('toJson 不写 subjectId', () {
      final json = session.toJson();
      expect(json.containsKey('subjectId'), isFalse);
    });

    test('fromJson 容忍旧数据里的 subjectId（默默忽略）', () {
      final legacy = <String, dynamic>{
        'id': 'legacy',
        'subjectId': 'computer',
        'durationMinutes': 30,
        'startTime': DateTime.utc(2026, 7, 1).toIso8601String(),
        'endTime': DateTime.utc(2026, 7, 1, 0, 30).toIso8601String(),
        'mode': FocusMode.pomodoro.index,
        'note': null,
      };
      final s = FocusSession.fromJson(legacy);
      expect(s.id, 'legacy');
      expect(s.durationMinutes, 30);
      expect(s.note, isNull);
    });

    test('roundtrip 干净数据', () {
      final json = session.toJson();
      final back = FocusSession.fromJson(json);
      expect(back.id, session.id);
      expect(back.durationMinutes, session.durationMinutes);
      expect(back.startTime, session.startTime);
      expect(back.endTime, session.endTime);
      expect(back.mode, session.mode);
      expect(back.note, session.note);
    });
  });
}
