import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/line_models.dart';
import 'line_cache_manager.dart';
import 'song_record.dart';

/// 乐谱数据仓库（支持本地 assets + 远程 Supabase）
class ChartRepository {
  static const String _chartsPath = 'assets/charts/';
  static const String _indexFile = 'songs_index.json';

  // 本地缓存子目录常量（与 LineCacheManager 保持一致）
  static const String _chartsDir = 'charts';
  static const String _audioDir = 'audio';
  static const String _coversDir = 'covers';

  static final Map<String, SongData> _memoryCache = {};
  static final LineCacheManager _cache = LineCacheManager();

  static SupabaseClient? _supabaseClient;

  /// 初始化 Supabase 客户端（需在 main() 中调用一次）
  static void initSupabase(String url, String anonKey) {
    _supabaseClient = SupabaseClient(url, anonKey);
  }

  static List<NoteEvent> _parseNotes(Map<String, dynamic> chartData) {
    final notesRaw = chartData['notes'] as List? ?? [];
    return notesRaw
        .whereType<Map<String, dynamic>>()
        .map((n) => NoteEvent.fromJson(n))
        .toList();
  }

  /// 加载歌曲列表：优先 Supabase，失败则降级到本地 assets
  static Future<List<SongData>> loadAllSongs() async {
    if (_supabaseClient != null) {
      try {
        final songs = await _loadFromSupabase();
        if (songs.isNotEmpty) return songs;
      } catch (e) {
        debugPrint('[ChartRepository] Supabase failed, fallback to local: $e');
      }
    }
    return _loadFromLocalAssets();
  }

  /// 从 Supabase songs 表加载
  static Future<List<SongData>> _loadFromSupabase() async {
    final client = _supabaseClient!;
    final response = await client.from('songs').select();

    final List<dynamic> rows = response as List<dynamic>;
    final songRecords = rows.map((r) => SongRecord.fromJson(r as Map<String, dynamic>)).toList();

    final songs = <SongData>[];
    for (final record in songRecords) {
      final chartJson = await _getChartJson(record.id, record.chartUrl);
      if (chartJson == null) continue;

      final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
      final notes = _parseNotes(chartData);

      songs.add(SongData(
        id: record.id,
        name: record.name,
        artist: record.artist,
        intro: record.intro,
        audioPath: record.audioUrl,
        coverPath: record.coverUrl,
        bpm: record.bpm,
        duration: record.durationMs ~/ 1000,
        difficulty: record.difficulty,
        dropDuration: record.dropDurationMs,
        notes: notes,
      ));
    }
    return songs;
  }

  /// 获取 chart JSON：优先本地缓存，其次远程下载
  static Future<String?> _getChartJson(String songId, String chartUrl) async {
    // 1. 尝试从本地 chart JSON 文件加载（适配旧逻辑）
    try {
      final local = await rootBundle.loadString('$_chartsPath$songId.json');
      return local;
    } catch (_) {}

    // 2. 尝试读取缓存文件
    final cached = await _cache.getCachedPath(_chartsDir, '$songId.json');
    if (cached != null) {
      return File(cached).readAsString();
    }

    // 3. 下载并缓存
    try {
      final localPath = await _cache.cacheFile(chartUrl, _chartsDir, '$songId.json');
      return File(localPath).readAsString();
    } catch (e) {
      debugPrint('[ChartRepository] Failed to load chart $songId: $e');
      return null;
    }
  }

  /// 从本地 assets 加载（降级路径）
  static Future<List<SongData>> _loadFromLocalAssets() async {
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
  }

  /// 根据 ID 加载单个歌曲
  static Future<SongData?> loadSong(String id) async {
    if (_memoryCache.containsKey(id)) {
      return _memoryCache[id];
    }

    if (_supabaseClient != null) {
      try {
        final response = await _supabaseClient!.from('songs').select().eq('id', id).single();
        final record = SongRecord.fromJson(response);
        final chartJson = await _getChartJson(record.id, record.chartUrl);
        if (chartJson == null) return null;

        final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
        final notes = _parseNotes(chartData);

        final song = SongData(
          id: record.id,
          name: record.name,
          artist: record.artist,
          intro: record.intro,
          audioPath: record.audioUrl,
          coverPath: record.coverUrl,
          bpm: record.bpm,
          duration: record.durationMs ~/ 1000,
          difficulty: record.difficulty,
          dropDuration: record.dropDurationMs,
          notes: notes,
        );
        _memoryCache[id] = song;
        return song;
      } catch (e) {
        debugPrint('[ChartRepository] loadSong from Supabase failed: $e');
      }
    }

    return _loadSongFromLocal(id);
  }

  static Future<SongData?> _loadSongFromLocal(String id) async {
    try {
      final chartJson = await rootBundle.loadString('$_chartsPath$id.json');
      final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
      final notes = _parseNotes(chartData);
      final song = SongData.fromJson(chartData, notes);
      _memoryCache[id] = song;
      return song;
    } catch (e) {
      debugPrint('Failed to load song $id: $e');
      return null;
    }
  }

  /// 预下载歌曲资源到本地缓存（播歌前调用）
  static Future<void> precacheSong(String songId, String audioUrl, String coverUrl, String chartUrl) async {
    try {
      final audioFile = audioUrl.split('/').last;
      await _cache.cacheFile(audioUrl, _audioDir, audioFile);
    } catch (e) {
      debugPrint('[ChartRepository] precache audio failed: $e');
    }
    try {
      final coverFile = coverUrl.split('/').last;
      await _cache.cacheFile(coverUrl, _coversDir, coverFile);
    } catch (e) {
      debugPrint('[ChartRepository] precache cover failed: $e');
    }
  }
}
