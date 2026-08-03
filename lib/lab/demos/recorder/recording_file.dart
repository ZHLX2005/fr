/// 录音文件元数据 —— 列表页(Read)用。
///
/// [duration] 可能为 null(未知)或来自两种来源:
/// [durationExact]=false 表示 bitrate 估算(O(1),固定 128kbps 误差 <1%);
/// =true 表示解码器实测(播放/预读时由 `just_audio` 写入)。
class RecordingFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;

  /// 时长;null = 未知。配合 [durationExact] 区分估算/实测。
  final Duration? duration;

  /// true = 解码器实测;false = bitrate 估算。
  final bool durationExact;

  /// 创建时间 —— 从文件名 `rec_2026-08-03T14-22-33.aac` 解析;失败 = null。
  final DateTime? createdAt;

  const RecordingFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
    this.duration,
    this.durationExact = false,
    this.createdAt,
  });

  double get sizeKb => sizeBytes / 1024;

  /// 可读化大小:≥1MB 显示 MB,否则 KB。
  String get sizeLabel => sizeBytes >= 1048576
      ? '${(sizeBytes / 1048576).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).toStringAsFixed(1)} KB';

  /// 展示用时间:优先创建时间,回落最后修改。
  DateTime get displayTime => createdAt ?? lastModified;

  RecordingFile copyWith({
    Duration? duration,
    bool? durationExact,
    DateTime? createdAt,
  }) {
    return RecordingFile(
      path: path,
      name: name,
      sizeBytes: sizeBytes,
      lastModified: lastModified,
      duration: duration ?? this.duration,
      durationExact: durationExact ?? this.durationExact,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
