import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/game_skin_meta.dart' show FileRef, kGameSkinIdPattern;
import '../io/line_song_spec.dart';

/// 曲目索引条目（对应 KV `line_song:index` 的一个元素）。
///
/// 大文件（audio / cover / chart）只存 [FileRef]；URL 由 [FileResolver] 派生。
class SongRecord {
  final String id;
  final String name;
  final String artist;
  final String intro;
  final FileRef audio;
  final FileRef cover;
  final FileRef chart;
  final int bpm;
  final int durationMs;
  final int difficulty;
  final int dropDurationMs;
  final int version;

  const SongRecord({
    required this.id,
    required this.name,
    required this.artist,
    required this.intro,
    required this.audio,
    required this.cover,
    required this.chart,
    required this.bpm,
    required this.durationMs,
    required this.difficulty,
    required this.dropDurationMs,
    this.version = 1,
  });

  String audioUrl(FileResolver r) => r.url(audio.fileId);
  String coverUrl(FileResolver r) => r.url(cover.fileId);
  String chartUrl(FileResolver r) => r.url(chart.fileId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': name,
        'artist': artist,
        'intro': intro,
        'bpm': bpm,
        'durationMs': durationMs,
        'difficulty': difficulty,
        'dropDurationMs': dropDurationMs,
        'version': version,
        'assets': {
          'audio': audio.toJson(),
          'cover': cover.toJson(),
          'chart': chart.toJson(),
        },
      };

  factory SongRecord.fromJson(Map<String, dynamic> json) {
    final assets = json['assets'];
    if (assets is! Map) {
      throw const FormatException('song record missing assets');
    }
    final map = Map<String, dynamic>.from(assets);
    FileRef requireAsset(String key) {
      final raw = map[key];
      if (raw is! Map) {
        throw FormatException('song record missing asset: $key');
      }
      return FileRef.fromJson(Map<String, dynamic>.from(raw));
    }

    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty || !kGameSkinIdPattern.hasMatch(id)) {
      throw FormatException('invalid song id: $id');
    }

    return SongRecord(
      id: id,
      name: (json['displayName'] as String?) ??
          (json['name'] as String?) ??
          'Unknown',
      artist: json['artist'] as String? ?? 'Unknown',
      intro: json['intro'] as String? ?? '',
      audio: requireAsset(kLineSongAssetAudio),
      cover: requireAsset(kLineSongAssetCover),
      chart: requireAsset(kLineSongAssetChart),
      bpm: (json['bpm'] as num?)?.toInt() ?? 120,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 180000,
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      dropDurationMs: (json['dropDurationMs'] as num?)?.toInt() ?? 2500,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  static List<SongRecord> parseListDecoded(List<dynamic> raw) {
    final seen = <String>{};
    final out = <SongRecord>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        final s = SongRecord.fromJson(Map<String, dynamic>.from(e));
        if (!seen.add(s.id)) continue;
        out.add(s);
      } catch (_) {
        // 单条损坏不拖垮整表
      }
    }
    return out;
  }
}
