import 'package:json_annotation/json_annotation.dart';

part 'lab_track_record.g.dart';

@JsonSerializable()
class LabTrackRecord {
  final String id;
  final String trackId;
  final String trackTitle;
  final String? customTitle;
  final DateTime startTime;
  final DateTime? endTime;
  final int totalDurationSeconds;
  final bool completed;
  final int? accumulatedSeconds;
  final int segmentIndex;            // last fully completed segment
  final List<int> perSegmentSeconds; // actual elapsed per segment

  /// 只有已完成的记录允许删除；运行中/暂停/提前结算未完成的都禁止（fr #1）。
  bool get canDelete => completed;

  LabTrackRecord({
    required this.id,
    required this.trackId,
    required this.trackTitle,
    this.customTitle,
    required this.startTime,
    this.endTime,
    required this.totalDurationSeconds,
    this.completed = false,
    this.accumulatedSeconds,
    required this.segmentIndex,
    required this.perSegmentSeconds,
  });

  factory LabTrackRecord.fromJson(Map<String, dynamic> json) =>
      _$LabTrackRecordFromJson(json);
  Map<String, dynamic> toJson() => _$LabTrackRecordToJson(this);

  LabTrackRecord copyWith({
    String? id,
    String? trackId,
    String? trackTitle,
    String? customTitle,
    DateTime? startTime,
    DateTime? endTime,
    int? totalDurationSeconds,
    bool? completed,
    int? accumulatedSeconds,
    int? segmentIndex,
    List<int>? perSegmentSeconds,
  }) {
    return LabTrackRecord(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      trackTitle: trackTitle ?? this.trackTitle,
      customTitle: customTitle ?? this.customTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      completed: completed ?? this.completed,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      perSegmentSeconds: perSegmentSeconds ?? this.perSegmentSeconds,
    );
  }
}