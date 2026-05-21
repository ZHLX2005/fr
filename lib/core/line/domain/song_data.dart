import 'note_event.dart';

/// 完整歌曲数据（含谱面）
class SongData {
  final String id;
  final String name;
  final String artist;
  final String intro;
  final String audioPath;
  final String coverPath;
  final int bpm;
  final int duration;
  final int difficulty;
  final int dropDuration;
  final List<NoteEvent> notes;

  const SongData({
    required this.id,
    required this.name,
    required this.artist,
    required this.intro,
    required this.audioPath,
    required this.coverPath,
    required this.bpm,
    required this.duration,
    required this.difficulty,
    required this.dropDuration,
    required this.notes,
  });

  factory SongData.fromJson(Map<String, dynamic> json, List<NoteEvent> notes) {
    final sortedNotes = List<NoteEvent>.from(notes)
      ..sort((a, b) => a.time.compareTo(b.time));
    return SongData(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      artist: json['artist'] as String? ?? 'Unknown',
      intro: json['intro'] as String? ?? '',
      audioPath: json['audioPath'] as String? ?? '',
      coverPath: json['coverPath'] as String? ?? '',
      bpm: json['bpm'] as int? ?? 120,
      duration: json['duration'] as int? ?? 180,
      difficulty: json['difficulty'] as int? ?? 1,
      dropDuration: json['dropDuration'] as int? ?? 2500,
      notes: sortedNotes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'intro': intro,
      'audioPath': audioPath,
      'coverPath': coverPath,
      'bpm': bpm,
      'duration': duration,
      'difficulty': difficulty,
      'dropDuration': dropDuration,
      'notes': notes
          .map(
            (n) => {
              'time': n.time,
              'column': n.column,
              'type': n.type.name,
              if (n.direction != null) 'direction': n.direction!.name,
              if (n.holdDuration != null) 'holdDuration': n.holdDuration,
            },
          )
          .toList(),
    };
  }
}
