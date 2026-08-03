import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

void main() {
  group('formatRecordDate', () {
    test('零填充到 YYYY-MM-DD HH:MM', () {
      final d = DateTime(2026, 8, 3, 9, 5);
      expect(formatRecordDate(d), '2026-08-03 09:05');
    });

    test('双位数月份/日期/时分不变', () {
      final d = DateTime(2026, 12, 31, 23, 59);
      expect(formatRecordDate(d), '2026-12-31 23:59');
    });
  });
}
