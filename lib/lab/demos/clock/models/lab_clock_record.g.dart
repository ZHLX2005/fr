// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_clock_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LabClockRecord _$LabClockRecordFromJson(Map<String, dynamic> json) =>
    LabClockRecord(
      id: json['id'] as String,
      clockId: json['clockId'] as String,
      clockTitle: json['clockTitle'] as String,
      customTitle: json['customTitle'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      completed: json['completed'] as bool? ?? false,
      accumulatedSeconds: (json['accumulatedSeconds'] as num?)?.toInt(),
    );

Map<String, dynamic> _$LabClockRecordToJson(LabClockRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'clockId': instance.clockId,
      'clockTitle': instance.clockTitle,
      'customTitle': instance.customTitle,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'durationSeconds': instance.durationSeconds,
      'completed': instance.completed,
      'accumulatedSeconds': instance.accumulatedSeconds,
    };
