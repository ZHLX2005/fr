/// 对应 Supabase songs 表的实体类
class SongRecord {
  final String id;
  final String name;
  final String artist;
  final String intro;
  final String audioUrl;
  final String coverUrl;
  final String chartUrl;
  final int bpm;
  final int durationMs;
  final int difficulty;
  final int dropDurationMs;

  const SongRecord({
    required this.id,
    required this.name,
    required this.artist,
    required this.intro,
    required this.audioUrl,
    required this.coverUrl,
    required this.chartUrl,
    required this.bpm,
    required this.durationMs,
    required this.difficulty,
    required this.dropDurationMs,
  });

  factory SongRecord.fromJson(Map<String, dynamic> json) {
    return SongRecord(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      artist: json['artist'] as String? ?? 'Unknown',
      intro: json['intro'] as String? ?? '',
      audioUrl: json['audio_url'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
      chartUrl: json['chart_url'] as String? ?? '',
      bpm: json['bpm'] as int? ?? 120,
      durationMs: json['duration_ms'] as int? ?? 180000,
      difficulty: json['difficulty'] as int? ?? 1,
      dropDurationMs: json['drop_duration_ms'] as int? ?? 2500,
    );
  }
}
