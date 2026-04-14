import 'package:json_annotation/json_annotation.dart';

part 'lab_note.g.dart';

@JsonSerializable()
class LabNote {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? color;

  LabNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.color,
  });

  factory LabNote.fromJson(Map<String, dynamic> json) =>
      _$LabNoteFromJson(json);

  Map<String, dynamic> toJson() => _$LabNoteToJson(this);

  LabNote copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? color,
  }) {
    return LabNote(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      color: color ?? this.color,
    );
  }
}
