import 'package:json_annotation/json_annotation.dart';

part 'lab_clock_record.g.dart';

@JsonSerializable()
class LabClockRecord {
  final String id;
  final String clockId;
  final String clockTitle;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final bool completed;
  final int? accumulatedSeconds;
  final int? startRemaining;  // 启动时的剩余秒数

  LabClockRecord({
    required this.id,
    required this.clockId,
    required this.clockTitle,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
    this.completed = false,
    this.accumulatedSeconds,
    this.startRemaining,
  });

  factory LabClockRecord.fromJson(Map<String, dynamic> json) => _$LabClockRecordFromJson(json);
  Map<String, dynamic> toJson() => _$LabClockRecordToJson(this);

  LabClockRecord copyWith({
    String? id,
    String? clockId,
    String? clockTitle,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    bool? completed,
    int? accumulatedSeconds,
    int? startRemaining,
  }) {
    return LabClockRecord(
      id: id ?? this.id,
      clockId: clockId ?? this.clockId,
      clockTitle: clockTitle ?? this.clockTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      completed: completed ?? this.completed,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      startRemaining: startRemaining ?? this.startRemaining,
    );
  }
}
