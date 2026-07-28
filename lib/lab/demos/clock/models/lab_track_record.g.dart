// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_track_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LabTrackRecord _$LabTrackRecordFromJson(Map<String, dynamic> json) =>
    LabTrackRecord(
      id: json['id'] as String,
      trackId: json['trackId'] as String,
      trackTitle: json['trackTitle'] as String,
      customTitle: json['customTitle'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      totalDurationSeconds: (json['totalDurationSeconds'] as num).toInt(),
      completed: json['completed'] as bool? ?? false,
      accumulatedSeconds: (json['accumulatedSeconds'] as num?)?.toInt(),
      segmentIndex: (json['segmentIndex'] as num).toInt(),
      perSegmentSeconds: (json['perSegmentSeconds'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(),
    );

Map<String, dynamic> _$LabTrackRecordToJson(LabTrackRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trackId': instance.trackId,
      'trackTitle': instance.trackTitle,
      'customTitle': instance.customTitle,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'totalDurationSeconds': instance.totalDurationSeconds,
      'completed': instance.completed,
      'accumulatedSeconds': instance.accumulatedSeconds,
      'segmentIndex': instance.segmentIndex,
      'perSegmentSeconds': instance.perSegmentSeconds,
    };
