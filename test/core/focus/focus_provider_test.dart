import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/focus/models/focus_session.dart';
import 'package:xiaodouzi_fr/core/focus/providers/focus_provider.dart';

void main() {
  late FocusProvider fp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fp = FocusProvider();
    await fp.init();
  });

  group('FocusProvider（无 subject 概念）', () {
    test('init 空 prefs 不崩，sessions 为空', () async {
      expect(fp.sessions, isEmpty);
      expect(fp.isLoading, isFalse);
    });

    test('init 容忍 legacy focus_subjects JSON（旧 key 被忽略）', () async {
      SharedPreferences.setMockInitialValues({
        'focus_subjects': '[{"id":"s1","name":"x","color":0,"iconIndex":0}]',
        'focus_sessions':
            '[{"id":"a","subjectId":"s1","durationMinutes":40,"startTime":"2026-07-29T08:00:00Z","endTime":"2026-07-29T08:40:00Z","mode":1,"note":null}]',
      });
      final fresh = FocusProvider();
      await fresh.init();
      expect(fresh.sessions.length, 1);
      expect(fresh.sessions.first.durationMinutes, 40);
    });

    test('addSession 后 getTodayMinutes 计入', () async {
      final now = DateTime.now();
      await fp.addSession(FocusSession(
        id: '1',
        durationMinutes: 30,
        startTime: DateTime(now.year, now.month, now.day, 9),
        endTime: DateTime(now.year, now.month, now.day, 9, 30),
        mode: FocusMode.freeTime,
      ));
      expect(fp.getTodayMinutes(), 30);
    });

    test('clearAll 清空 sessions', () async {
      await fp.addSession(FocusSession(
        id: 'x',
        durationMinutes: 5,
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(minutes: 5)),
        mode: FocusMode.freeTime,
      ));
      await fp.clearAll();
      expect(fp.sessions, isEmpty);
    });
  });
}
