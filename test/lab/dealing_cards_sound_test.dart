import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';

void main() {
  group('DealingCardsSound', () {
    test('enabled 默认 true', () {
      expect(DealingCardsSound.enabled, isTrue);
    });

    test('setEnabled(false) 后 enabled 变 false', () {
      DealingCardsSound.setEnabled(false);
      expect(DealingCardsSound.enabled, isFalse);
    });

    test('setEnabled(true) 后 enabled 变 true', () {
      DealingCardsSound.setEnabled(false);
      DealingCardsSound.setEnabled(true);
      expect(DealingCardsSound.enabled, isTrue);
    });

    test('poolSize 至少 16（覆盖 6 人 Coup 满员）', () {
      expect(DealingCardsSound.poolSize, greaterThanOrEqualTo(16));
    });
  });
}
