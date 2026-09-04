// lib/core/game_kit/skin/game_skin_prefs.dart
//
// Generic skin prefs (SharedPreferences) — parameterized by GameSkinSpec.

import 'package:shared_preferences/shared_preferences.dart';

import 'game_skin_spec.dart';

class GameSkinPrefs {
  GameSkinPrefs._();

  static Future<String> read(
    GameSkinSpec spec, {
    required String fallbackId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(spec.prefsKey) ?? fallbackId;
  }

  static Future<void> write(GameSkinSpec spec, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(spec.prefsKey, id);
  }

  static Future<void> clear(GameSkinSpec spec) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(spec.prefsKey);
  }
}
