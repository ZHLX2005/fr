// test/native/home_widget/clock_widget_data_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/native/home_widget/clock_widget_data.dart';

void main() {
  group('ClockWidgetData.isPausedAtStart', () {
    test('空数据 isPausedAtStart=false', () {
      expect(ClockWidgetData.empty.isPausedAtStart, isFalse);
    });
    test('新建后从未启动（!isRunning && remaining == duration）→ true', () {
      final d = ClockWidgetData.fromClock(
        title: 't',
        remainingSeconds: 60,
        durationSeconds: 60,
        isRunning: false,
        color: '#D4644B',
      );
      expect(d.isPausedAtStart, isTrue);
    });
    test('中途暂停（!isRunning && remaining < duration）→ false', () {
      final d = ClockWidgetData.fromClock(
        title: 't',
        remainingSeconds: 30,
        durationSeconds: 60,
        isRunning: false,
        color: '#D4644B',
      );
      expect(d.isPausedAtStart, isFalse);
    });
    test('运行中 → false', () {
      final d = ClockWidgetData.fromClock(
        title: 't',
        remainingSeconds: 30,
        durationSeconds: 60,
        isRunning: true,
        color: '#D4644B',
      );
      expect(d.isPausedAtStart, isFalse);
    });
    test('toMap 包含 isPausedAtStart 键值（空数据 → 0）', () {
      expect(ClockWidgetData.empty.toMap()['isPausedAtStart'], 0);
    });
  });
}