/// 从旧 `lib/services/minimax_speech_service.dart` 迁移，语义一致。
///
/// 合成参数。
class SynthesisParams {
  final String text;
  final String voiceId;
  final String model;
  final double speed;
  final double vol;
  final double pitch;
  final int sampleRate;
  final int bitrate;
  final String format;
  final int channel;
  final bool englishNormalization;
  final void Function(List<int> chunk)? onChunk;
  final void Function(TaskState state)? onStateChanged;

  const SynthesisParams({
    required this.text,
    this.voiceId = 'female-yujie',
    this.model = 'speech-2.8-hd',
    this.speed = 1.0,
    this.vol = 1.0,
    this.pitch = 0,
    this.sampleRate = 32000,
    this.bitrate = 128000,
    this.format = 'mp3',
    this.channel = 1,
    this.englishNormalization = false,
    this.onChunk,
    this.onStateChanged,
  });
}

/// 任务状态。
enum TaskState {
  idle,
  connecting,
  synthesizing,
  finished,
  error,
  interrupted,
}

/// 任务快照。
class SynthesisTaskInfo {
  final String taskId;
  final TaskState state;
  final String text;
  final String voiceId;
  final int chunkCount;
  final int totalBytes;
  final String? errorMessage;
  final DateTime? startTime;

  const SynthesisTaskInfo({
    required this.taskId,
    required this.state,
    required this.text,
    required this.voiceId,
    required this.chunkCount,
    required this.totalBytes,
    this.errorMessage,
    this.startTime,
  });
}
