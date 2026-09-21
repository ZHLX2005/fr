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
  final int? bpm;          // 20..300, null = no beat
  final String? beatPattern; // key into MetronomePresets.patterns, null = no beat

  /// 血缘父 clock 的 id：从某条记录"新建"时钟时，父 = 该记录所属的 clock。
  /// null = 链根（独立时钟，另起一条链）。max 模式按这条链合并取最大时长。
  ///
  /// 注意：copyWith 是 `x ?? this.x` 范式，传 null 无法清空本字段 ——
  /// 置空请走 LabClockProvider.setClockParent(id, null)。
  final String? parentId;

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
    this.bpm,
    this.beatPattern,
    this.parentId,
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
    int? bpm,
    String? beatPattern,
    String? parentId,
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
      bpm: bpm ?? this.bpm,
      beatPattern: beatPattern ?? this.beatPattern,
      parentId: parentId ?? this.parentId,
    );
  }

  /// 显式设置 [parentId]（可为 null）。
  ///
  /// copyWith 是 `x ?? this.x` 范式，传 null **无法**清空 parentId；
  /// 而"脱离链成为新根"必须能把 parentId 置回 null —— 用独立方法表达该意图，
  /// 避免后人误用 copyWith(parentId: null) 写出静默失效的代码。
  LabClock withParentId(String? parentId) {
    return LabClock(
      id: id,
      title: title,
      description: description,
      createdAt: createdAt,
      targetTime: targetTime,
      durationSeconds: durationSeconds,
      isRunning: isRunning,
      remainingSeconds: remainingSeconds,
      color: color,
      startTime: startTime,
      startRemainingSeconds: startRemainingSeconds,
      bpm: bpm,
      beatPattern: beatPattern,
      parentId: parentId,
    );
  }
}
