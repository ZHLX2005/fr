import 'note_event.dart';

/// 谱面数据（不可变）
class ChartData {
  final String name;
  final int bpm;
  final int dropDuration;
  final List<NoteEvent> notes;

  const ChartData({
    required this.name,
    required this.bpm,
    required this.dropDuration,
    required this.notes,
  });

  factory ChartData.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['notes'] as List;
    final notes = (rawNotes)
        .whereType<Map<String, dynamic>>()
        .map((n) => NoteEvent.fromJson(n))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return ChartData(
      name: json['name'] as String? ?? 'Unnamed',
      bpm: json['bpm'] as int? ?? 120,
      dropDuration: json['dropDuration'] as int? ?? 2500,
      notes: notes,
    );
  }
}
