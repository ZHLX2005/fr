import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/line_models.dart';
import 'line_cache_manager.dart';
import 'song_record.dart';

/// 乐谱数据仓库（远程 Supabase + 本地文件缓存）
class ChartRepository {
  // 本地缓存子目录常量
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

  /// 加载歌曲列表（从 Supabase songs 表）
  static Future<List<SongData>> loadAllSongs() async {
    if (_supabaseClient == null) {
      debugPrint('[ChartRepository] Supabase not initialized');
      return [];
    }
    try {
      return await _loadFromSupabase();
    } catch (e) {
      debugPrint('[ChartRepository] Failed to load songs: $e');
      return [];
    }
  }

  /// 从 Supabase songs 表加载
  static Future<List<SongData>> _loadFromSupabase() async {
    final client = _supabaseClient!;
    final response = await client.from('music').select();

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

  /// 获取 chart JSON：优先缓存文件，其次从 Supabase Storage 下载
  static Future<String?> _getChartJson(String songId, String chartUrl) async {
    // 1. 尝试读取缓存文件
    final cached = await _cache.getCachedPath(_chartsDir, '$songId.json');
    if (cached != null) {
      return File(cached).readAsString();
    }

    // 2. 下载并缓存
    try {
      final localPath = await _cache.cacheFile(chartUrl, _chartsDir, '$songId.json');
      return File(localPath).readAsString();
    } catch (e) {
      debugPrint('[ChartRepository] Failed to load chart $songId: $e');
      return null;
    }
  }

  /// 根据 ID 加载单个歌曲
  static Future<SongData?> loadSong(String id) async {
    if (_memoryCache.containsKey(id)) {
      return _memoryCache[id];
    }

    if (_supabaseClient == null) {
      debugPrint('[ChartRepository] Supabase not initialized');
      return null;
    }

    try {
      final response = await _supabaseClient!.from('music').select().eq('id', id).single();
      final record = SongRecord.fromJson(Map<String, dynamic>.from(response));
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
      debugPrint('[ChartRepository] loadSong failed: $e');
      return null;
    }
  }

  /// 预下载歌曲资源到本地缓存
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
