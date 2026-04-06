import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/line_models.dart';

/// 乐谱数据仓库
class ChartRepository {
  static const String _chartsPath = 'assets/charts/';
  static const String _indexFile = 'songs_index.json';

  static final Map<String, SongData> _cache = {};

  static List<NoteEvent> _parseNotes(Map<String, dynamic> chartData) {
    final notesRaw = chartData['notes'] as List? ?? [];
    return notesRaw
        .whereType<Map<String, dynamic>>()
        .map((n) => NoteEvent.fromJson(n))
        .toList();
  }

  /// 加载歌曲索引
  static Future<List<SongData>> loadAllSongs() async {
    try {
      final indexJson = await rootBundle.loadString('$_chartsPath$_indexFile');
      final indexData = jsonDecode(indexJson) as Map<String, dynamic>;
      final songsList = indexData['songs'] as List? ?? [];

      final songs = <SongData>[];
      for (final songInfo in songsList) {
        final songId = songInfo['id'] as String;
        final chartJson = await rootBundle.loadString('$_chartsPath$songId.json');
        final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
        final notes = _parseNotes(chartData);

        songs.add(SongData.fromJson(chartData, notes));
      }
      return songs;
    } catch (e) {
      debugPrint('Failed to load songs: $e');
      return [];
    }
  }

  /// 根据ID加载单个歌曲
  static Future<SongData?> loadSong(String id) async {
    if (_cache.containsKey(id)) {
      return _cache[id];
    }
    try {
      final chartJson = await rootBundle.loadString('$_chartsPath$id.json');
      final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
      final notes = _parseNotes(chartData);

      final song = SongData.fromJson(chartData, notes);
      _cache[id] = song;
      return song;
    } catch (e) {
      debugPrint('Failed to load song $id: $e');
      return null;
    }
  }
}
