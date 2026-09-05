import 'package:shared_preferences/shared_preferences.dart';

import 'game_result.dart';

/// 曲目清谱奖牌：无 < Clear < FC < AP
enum SongMedal { none, clear, fullCombo, allPerfect }

extension SongMedalX on SongMedal {
  int get rank => index;

  String get label => switch (this) {
        SongMedal.none => '',
        SongMedal.clear => 'CLEAR',
        SongMedal.fullCombo => 'FC',
        SongMedal.allPerfect => 'AP',
      };
}

class SongMedalStore {
  static String _key(String songId) => 'line_medal_$songId';

  static Future<SongMedal> load(String songId) async {
    if (songId.isEmpty) return SongMedal.none;
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key(songId)) ?? 0;
    return SongMedal.values[v.clamp(0, SongMedal.values.length - 1)];
  }

  static Future<Map<String, SongMedal>> loadMany(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, SongMedal>{};
    for (final id in ids) {
      if (id.isEmpty) continue;
      final v = prefs.getInt(_key(id)) ?? 0;
      out[id] = SongMedal.values[v.clamp(0, SongMedal.values.length - 1)];
    }
    return out;
  }

  static Future<SongMedal> record(String songId, GameResult result) async {
    if (songId.isEmpty || !result.cleared) {
      return load(songId);
    }
    final next = result.isAllPerfect
        ? SongMedal.allPerfect
        : (result.isFullCombo ? SongMedal.fullCombo : SongMedal.clear);
    final prefs = await SharedPreferences.getInstance();
    final prevRank = prefs.getInt(_key(songId)) ?? 0;
    if (next.rank > prevRank) {
      await prefs.setInt(_key(songId), next.index);
      return next;
    }
    return SongMedal.values[prevRank.clamp(0, SongMedal.values.length - 1)];
  }
}
