import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';

void main() {
  group('DealingCardsSound toggle', () {
    test('default enabled is true', () {
      expect(DealingCardsSound.enabled, isTrue);
    });

    test('setEnabled(false) silences subsequent play()', () async {
      DealingCardsSound.setEnabled(false);
      expect(DealingCardsSound.enabled, isFalse);
      // Fire-and-forget, must not throw and must not produce audio.
      await DealingCardsSound.play();
      // restore so other tests aren't affected
      DealingCardsSound.setEnabled(true);
      expect(DealingCardsSound.enabled, isTrue);
    });
  });
}
