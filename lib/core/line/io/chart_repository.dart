import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/public_kv_reader.dart';
import '../cache/line_cache_manager.dart';
import '../domain/note_event.dart';
import '../domain/song_data.dart';
import '../domain/song_record.dart';
import 'line_song_spec.dart';

/// 乐谱数据仓库（KV public index + File API + 本地缓存）
class ChartRepository {
  static const String _chartsDir = 'charts';
  static const String _audioDir = 'audio';
  static const String _coversDir = 'covers';

  static final Map<String, SongData> _memoryCache = {};
  static final LineCacheManager _cache = LineCacheManager();

  static PublicKvReader? _kv;
  static FileResolver? _files;
  static String _baseUrl = kDefaultLineSongBaseUrl;

  /// 配置 KV / File 后端（可选；未调则用默认 host）。
  static void configure({
    String baseUrl = kDefaultLineSongBaseUrl,
    PublicKvReader? reader,
    FileResolver? resolver,
  }) {
    _baseUrl = baseUrl;
    _kv = reader ?? lineSongKvReader(baseUrl: baseUrl);
    _files = resolver ?? lineSongFileResolver(baseUrl: baseUrl);
  }

  static PublicKvReader get _kvReader =>
      _kv ?? lineSongKvReader(baseUrl: _baseUrl);

  static FileResolver get _fileResolver =>
      _files ?? lineSongFileResolver(baseUrl: _baseUrl);

  static List<NoteEvent> _parseNotes(Map<String, dynamic> chartData) {
    final notesRaw = chartData['notes'] as List? ?? [];
    return notesRaw
        .whereType<Map<String, dynamic>>()
        .map((n) => NoteEvent.fromJson(n))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// 拉取 `line_song:index`；失败时尝试本地 index 缓存。
  static Future<List<SongRecord>> loadIndex() async {
    final jsonText = await _kvReader.readString(kLineSongKvIndexKey);
    if (jsonText != null) {
      await _cache.cacheSongsIndex(jsonText);
      return _parseIndex(jsonText);
    }
    final cached = await _cache.readCachedSongsIndex();
    if (cached != null) {
      debugPrint('[ChartRepository] KV miss → using cached line_song:index');
      return _parseIndex(cached);
    }
    debugPrint('[ChartRepository] line_song:index unavailable');
    return [];
  }

  static List<SongRecord> _parseIndex(String jsonText) {
    try {
      final raw = jsonDecode(jsonText);
      if (raw is! List) return [];
      return SongRecord.parseListDecoded(raw);
    } catch (e) {
      debugPrint('[ChartRepository] parse index failed: $e');
      return [];
    }
  }

  /// 加载歌曲列表（index + 各曲 chart；audio/cover 仅填 URL）
  static Future<List<SongData>> loadAllSongs() async {
    try {
      final records = await loadIndex();
      final songs = <SongData>[];
      for (final record in records) {
        final song = await _songFromRecord(record, loadChart: true);
        if (song != null) songs.add(song);
      }
      return songs;
    } catch (e) {
      debugPrint('[ChartRepository] Failed to load songs: $e');
      return [];
    }
  }

  static Future<SongData?> _songFromRecord(
    SongRecord record, {
    required bool loadChart,
  }) async {
    List<NoteEvent> notes = const [];
    var bpm = record.bpm;
    var duration = (record.durationMs / 1000).round();
    var difficulty = record.difficulty;
    var dropDuration = record.dropDurationMs;
    var name = record.name;
    var artist = record.artist;
    var intro = record.intro;

    if (loadChart) {
      final chartJson = await _getChartJson(record);
      if (chartJson == null) return null;
      final chartData = jsonDecode(chartJson) as Map<String, dynamic>;
      notes = _parseNotes(chartData);
      name = chartData['name'] as String? ?? name;
      artist = chartData['artist'] as String? ?? artist;
      intro = chartData['intro'] as String? ?? intro;
      bpm = chartData['bpm'] as int? ?? bpm;
      duration = chartData['duration'] as int? ?? duration;
      difficulty = chartData['difficulty'] as int? ?? difficulty;
      dropDuration = chartData['dropDuration'] as int? ?? dropDuration;
    }

    return SongData(
      id: record.id,
      name: name,
      artist: artist,
      intro: intro,
      audioPath: record.audioUrl(_fileResolver),
      coverPath: record.coverUrl(_fileResolver),
      bpm: bpm,
      duration: duration,
      difficulty: difficulty,
      dropDuration: dropDuration,
      notes: notes,
    );
  }

  /// 获取 chart JSON：优先按 fileId 命中缓存，否则从 File API 下载。
  static Future<String?> _getChartJson(SongRecord record) async {
    final fileName = '${record.chart.fileId}.json';
    final cached = await _cache.getCachedPath(_chartsDir, fileName);
    if (cached != null) {
      return File(cached).readAsString();
    }
    try {
      final url = record.chartUrl(_fileResolver);
      final localPath = await _cache.cacheFile(url, _chartsDir, fileName);
      return File(localPath).readAsString();
    } catch (e) {
      debugPrint('[ChartRepository] Failed to load chart ${record.id}: $e');
      return null;
    }
  }

  /// 根据 ID 加载单个歌曲
  static Future<SongData?> loadSong(String id) async {
    if (_memoryCache.containsKey(id)) return _memoryCache[id];
    try {
      final record = await loadSongRecord(id);
      if (record == null) return null;
      final song = await _songFromRecord(record, loadChart: true);
      if (song != null) _memoryCache[id] = song;
      return song;
    } catch (e) {
      debugPrint('[ChartRepository] loadSong failed: $e');
      return null;
    }
  }

  /// 预下载歌曲资源到本地缓存（按 fileId 命名）
  static Future<void> precacheSong(SongRecord record) async {
    Future<void> one(String url, String dir, String name) async {
      try {
        await _cache.cacheFile(url, dir, name);
      } catch (e) {
        debugPrint('[ChartRepository] precache $name failed: $e');
      }
    }

    await one(
      record.audioUrl(_fileResolver),
      _audioDir,
      _audioFileName(record),
    );
    await one(
      record.coverUrl(_fileResolver),
      _coversDir,
      _coverFileName(record),
    );
    await one(
      record.chartUrl(_fileResolver),
      _chartsDir,
      '${record.chart.fileId}.json',
    );
  }

  static String _audioFileName(SongRecord r) {
    final ext = _extOf(r.audio.fileName, '.m4a');
    return '${r.audio.fileId}$ext';
  }

  static String _coverFileName(SongRecord r) {
    final ext = _extOf(r.cover.fileName, '.webp');
    return '${r.cover.fileId}$ext';
  }

  static String _extOf(String name, String fallback) {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return fallback;
    return name.substring(i);
  }

  /// 检查歌曲资源是否已缓存本地（audio + chart）
  static Future<bool> isSongCached(SongRecord record) async {
    final audioCached = await _cache.getCachedPath(
      _audioDir,
      _audioFileName(record),
    );
    final chartCached = await _cache.getCachedPath(
      _chartsDir,
      '${record.chart.fileId}.json',
    );
    return audioCached != null && chartCached != null;
  }

  /// 解析已缓存的本地音频路径（未缓存返回 null）
  static Future<String?> cachedAudioPath(SongRecord record) =>
      _cache.getCachedPath(_audioDir, _audioFileName(record));

  /// 下载 audio（带进度），返回本地路径
  static Future<String> downloadAudio(
    SongRecord record, {
    void Function(double progress)? onProgress,
  }) {
    return _cache.downloadFile(
      record.audioUrl(_fileResolver),
      _audioDir,
      _audioFileName(record),
      onProgress: onProgress,
    );
  }

  /// 下载 chart（带进度），返回本地路径
  static Future<String> downloadChart(
    SongRecord record, {
    void Function(double progress)? onProgress,
  }) {
    return _cache.downloadFile(
      record.chartUrl(_fileResolver),
      _chartsDir,
      '${record.chart.fileId}.json',
      onProgress: onProgress,
    );
  }

  /// 获取单个歌曲的 SongRecord（不加载 chart JSON）
  static Future<SongRecord?> loadSongRecord(String id) async {
    final records = await loadIndex();
    for (final r in records) {
      if (r.id == id) return r;
    }
    return null;
  }
}
