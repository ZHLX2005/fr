// lib/core/chess/skins/chess_skin_prefs.dart
//
// Thin compat wrapper over game_kit/skin/game_skin_prefs.dart.
// Preserves ChessSkinPrefs.read()/write() signature.

import '../../game_kit/skin/game_skin_prefs.dart' as g;
import '../../game_kit/skin/game_skin_spec.dart';
import 'chess_skin_meta.dart';

class ChessSkinPrefs {
  ChessSkinPrefs._();

  static Future<String> read() =>
      g.GameSkinPrefs.read(kChessSkinSpec, fallbackId: kChessSkinsCatalog.first.id);

  static Future<void> write(String id) => g.GameSkinPrefs.write(kChessSkinSpec, id);
}
