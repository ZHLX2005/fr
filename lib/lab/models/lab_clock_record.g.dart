// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_clock_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClockEvent _$ClockEventFromJson(Map<String, dynamic> json) => ClockEvent(
  type: $enumDecode(_$ClockEventTypeEnumMap, json['type']),
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$ClockEventToJson(ClockEvent instance) =>
    <String, dynamic>{
      'type': _$ClockEventTypeEnumMap[instance.type]!,
      'timestamp': instance.timestamp.toIso8601String(),
    };

const _$ClockEventTypeEnumMap = {
  ClockEventType.start: 'start',
  ClockEventType.pause: 'pause',
  ClockEventType.resume: 'resume',
  ClockEventType.reset: 'reset',
};

LabClockRecord _$LabClockRecordFromJson(Map<String, dynamic> json) =>
    LabClockRecord(
      id: json['id'] as String,
      clockId: json['clockId'] as String,
      clockTitle: json['clockTitle'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      completed: json['completed'] as bool? ?? false,
      events: (json['events'] as List<dynamic>?)
          ?.map((e) => ClockEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$LabClockRecordToJson(LabClockRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'clockId': instance.clockId,
      'clockTitle': instance.clockTitle,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'durationSeconds': instance.durationSeconds,
      'completed': instance.completed,
      'events': instance.events,
    };
