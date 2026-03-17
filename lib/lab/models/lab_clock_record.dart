import 'package:json_annotation/json_annotation.dart';

part 'lab_clock_record.g.dart';

@JsonSerializable()
class LabClockRecord {
  final String id;
  final String clockId;
  final String clockTitle;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds; // 本次倒计时时长（秒）
  final bool completed; // 是否完成
  final int accumulatedRunningSeconds; // 累计实际运行时间（秒）

  LabClockRecord({
    required this.id,
    required this.clockId,
    required this.clockTitle,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
    this.completed = false,
    this.accumulatedRunningSeconds = 0,
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
    int? accumulatedRunningSeconds,
  }) {
    return LabClockRecord(
      id: id ?? this.id,
      clockId: clockId ?? this.clockId,
      clockTitle: clockTitle ?? this.clockTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      completed: completed ?? this.completed,
      accumulatedRunningSeconds: accumulatedRunningSeconds ?? this.accumulatedRunningSeconds,
    );
  }

  /// 获取实际使用时长（秒）- 返回累计运行时间
  int get actualDuration => accumulatedRunningSeconds;
}
