import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

void main() {
  group('LabClockProvider.resolveColor', () {
    test('无颜色 → 主题默认陶土色 #D4644B（非蓝）', () {
      expect(LabClockProvider.resolveColor(null), '#D4644B');
    });
    test('有颜色 → 原样返回，不覆盖用户选择', () {
      expect(LabClockProvider.resolveColor('#7A9A7E'), '#7A9A7E');
    });
    test('默认色常量即编辑器色板首色', () {
      expect(LabClockProvider.kDefaultClockColor, '#D4644B');
    });
  });
}
