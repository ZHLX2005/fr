import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/sample_loader.dart';

void main() {
  group('slot 默认值', () {
    test('weak/medium 默认合成(0)，accent 默认木鱼(1)', () {
      expect(SampleLoader.slotDefault(0), 0);
      expect(SampleLoader.slotDefault(1), 0);
      expect(SampleLoader.slotDefault(2), 1);
    });
  });

  group('resolveSoundId', () {
    test('用户存了木鱼(1) → 1', () {
      expect(SampleLoader.resolveSoundId(1, 0), 1);
    });
    test('用户存了合成(0) → 0（尊重用户显式选择）', () {
      expect(SampleLoader.resolveSoundId(0, 2), 0);
    });
    test('没存过 → 用默认（accent=1，其余=0）', () {
      expect(SampleLoader.resolveSoundId(null, 2), 1);
      expect(SampleLoader.resolveSoundId(null, 0), 0);
    });
  });
}
