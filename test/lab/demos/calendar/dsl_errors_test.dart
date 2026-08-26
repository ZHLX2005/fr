import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_errors.dart';

void main() {
  group('Position', () {
    test('toString formats as line N, col M', () {
      expect(const Position(2, 5).toString(), 'line 2, col 5');
    });

    test('equality and hashCode', () {
      expect(const Position(1, 1), equals(const Position(1, 1)));
      expect(const Position(1, 1).hashCode, const Position(1, 1).hashCode);
    });
  });

  group('DslError', () {
    test('with hint appends hint to toString', () {
      expect(
        const DslError(Position(1, 1), 'bad', 'try /day=15').toString(),
        'line 1, col 1: bad (try /day=15)',
      );
    });

    test('without hint omits parentheses', () {
      expect(const DslError(Position(3, 2), 'oops').toString(), 'line 3, col 2: oops');
    });
  });
}