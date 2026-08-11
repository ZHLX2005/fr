import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

void main() {
  group('LabClockProvider.crossedZero', () {
    test('3 → 0 归零瞬间触发', () {
      expect(LabClockProvider.crossedZero(3, 0), isTrue);
    });
    test('1 → -2 跨过归零触发', () {
      expect(LabClockProvider.crossedZero(1, -2), isTrue);
    });
    test('已归零 0 → -1 不重复触发', () {
      expect(LabClockProvider.crossedZero(0, -1), isFalse);
    });
    test('负数持续 -5 → -6 不触发', () {
      expect(LabClockProvider.crossedZero(-5, -6), isFalse);
    });
    test('未归零 5 → 3 不触发', () {
      expect(LabClockProvider.crossedZero(5, 3), isFalse);
    });
  });
}
