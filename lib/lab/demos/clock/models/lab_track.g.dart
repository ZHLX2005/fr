// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LabTrack _$LabTrackFromJson(Map<String, dynamic> json) => LabTrack(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String? ?? '',
  createdAt: DateTime.parse(json['createdAt'] as String),
  segments: (json['segments'] as List<dynamic>)
      .map((e) => LabTrackSegment.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$LabTrackToJson(LabTrack instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'description': instance.description,
  'createdAt': instance.createdAt.toIso8601String(),
  'segments': instance.segments,
};

LabTrackSegment _$LabTrackSegmentFromJson(Map<String, dynamic> json) =>
    LabTrackSegment(
      clockId: json['clockId'] as String,
      snapshotTitle: json['snapshotTitle'] as String,
      snapshotColor: json['snapshotColor'] as String?,
      snapshotDurationSeconds: (json['snapshotDurationSeconds'] as num).toInt(),
      snapshotBpm: (json['snapshotBpm'] as num?)?.toInt(),
      snapshotBeatPattern: json['snapshotBeatPattern'] as String?,
    );

Map<String, dynamic> _$LabTrackSegmentToJson(LabTrackSegment instance) =>
    <String, dynamic>{
      'clockId': instance.clockId,
      'snapshotTitle': instance.snapshotTitle,
      'snapshotColor': instance.snapshotColor,
      'snapshotDurationSeconds': instance.snapshotDurationSeconds,
      'snapshotBpm': instance.snapshotBpm,
      'snapshotBeatPattern': instance.snapshotBeatPattern,
    };
