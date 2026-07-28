import 'package:json_annotation/json_annotation.dart';

part 'lab_track.g.dart';

@JsonSerializable()
class LabTrack {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<LabTrackSegment> segments;

  LabTrack({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    required this.segments,
  });

  factory LabTrack.fromJson(Map<String, dynamic> json) => _$LabTrackFromJson(json);

  Map<String, dynamic> toJson() {
    final generated = _$LabTrackToJson(this);
    // json_serializable 6.x does not auto-call toJson() on `List<JsonSerializable>`
    // fields; serialize segments manually so JSON encoding works.
    generated['segments'] = segments.map((e) => e.toJson()).toList();
    return generated;
  }

  LabTrack copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    List<LabTrackSegment>? segments,
  }) {
    return LabTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      segments: segments ?? this.segments,
    );
  }
}

@JsonSerializable()
class LabTrackSegment {
  /// Reference to the source clock. May point to a deleted clock;
  /// track playback uses snapshot fields, not the live clock.
  final String clockId;

  /// Snapshotted at add-time so editing the original clock doesn't break the track.
  final String snapshotTitle;
  final String? snapshotColor;
  final int snapshotDurationSeconds;
  final int? snapshotBpm;
  final String? snapshotBeatPattern;

  LabTrackSegment({
    required this.clockId,
    required this.snapshotTitle,
    this.snapshotColor,
    required this.snapshotDurationSeconds,
    this.snapshotBpm,
    this.snapshotBeatPattern,
  });

  factory LabTrackSegment.fromJson(Map<String, dynamic> json) =>
      _$LabTrackSegmentFromJson(json);
  Map<String, dynamic> toJson() => _$LabTrackSegmentToJson(this);
}
