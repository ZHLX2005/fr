import 'package:json_annotation/json_annotation.dart';

part 'lab_clock_record.g.dart';

@JsonSerializable()
class LabClockRecord {
  final String id;
  final String clockId;
  final String clockTitle;
  final String? customTitle; // 自定义名称
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final bool completed;
  final int? accumulatedSeconds;

  LabClockRecord({
    required this.id,
    required this.clockId,
    required this.clockTitle,
    this.customTitle,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
    this.completed = false,
    this.accumulatedSeconds,
  });

  factory LabClockRecord.fromJson(Map<String, dynamic> json) =>
      _$LabClockRecordFromJson(json);
  Map<String, dynamic> toJson() => _$LabClockRecordToJson(this);

  LabClockRecord copyWith({
    String? id,
    String? clockId,
    String? clockTitle,
    String? customTitle,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    bool? completed,
    int? accumulatedSeconds,
  }) {
    return LabClockRecord(
      id: id ?? this.id,
      clockId: clockId ?? this.clockId,
      clockTitle: clockTitle ?? this.clockTitle,
      customTitle: customTitle ?? this.customTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      completed: completed ?? this.completed,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
    );
  }
}
