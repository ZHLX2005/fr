// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_clock.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LabClock _$LabClockFromJson(Map<String, dynamic> json) => LabClock(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String? ?? '',
  createdAt: DateTime.parse(json['createdAt'] as String),
  targetTime: json['targetTime'] as String?,
  durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
  isRunning: json['isRunning'] as bool? ?? false,
  remainingSeconds: (json['remainingSeconds'] as num?)?.toInt() ?? 0,
  color: json['color'] as String?,
  startTime: json['startTime'] == null
      ? null
      : DateTime.parse(json['startTime'] as String),
  startRemainingSeconds: (json['startRemainingSeconds'] as num?)?.toInt(),
);

Map<String, dynamic> _$LabClockToJson(LabClock instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'description': instance.description,
  'createdAt': instance.createdAt.toIso8601String(),
  'targetTime': instance.targetTime,
  'durationSeconds': instance.durationSeconds,
  'isRunning': instance.isRunning,
  'remainingSeconds': instance.remainingSeconds,
  'color': instance.color,
  'startTime': instance.startTime?.toIso8601String(),
  'startRemainingSeconds': instance.startRemainingSeconds,
};
