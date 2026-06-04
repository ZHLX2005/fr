import 'package:json_annotation/json_annotation.dart';

part 'lab_clock.g.dart';

@JsonSerializable()
class LabClock {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final String? targetTime; // 目标时间 (HH:mm)
  final int? durationSeconds; // 倒计时时长（秒）
  final bool isRunning;
  final int remainingSeconds; // 剩余秒数
  final String? color;
  final DateTime? startTime; // 开始倒计时的时间
  final int? startRemainingSeconds; // 启动时刻的剩余秒数（用于后台恢复计算）

  LabClock({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.targetTime,
    this.durationSeconds,
    this.isRunning = false,
    this.remainingSeconds = 0,
    this.color,
    this.startTime,
    this.startRemainingSeconds,
  });

  factory LabClock.fromJson(Map<String, dynamic> json) =>
      _$LabClockFromJson(json);

  Map<String, dynamic> toJson() => _$LabClockToJson(this);

  LabClock copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    String? targetTime,
    int? durationSeconds,
    bool? isRunning,
    int? remainingSeconds,
    String? color,
    DateTime? startTime,
    int? startRemainingSeconds,
  }) {
    return LabClock(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      targetTime: targetTime ?? this.targetTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isRunning: isRunning ?? this.isRunning,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      color: color ?? this.color,
      startTime: startTime ?? this.startTime,
      startRemainingSeconds:
          startRemainingSeconds ?? this.startRemainingSeconds,
    );
  }
}
