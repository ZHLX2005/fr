import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// MiniMax 语音合成服务（纯数据控制层，无 UI）
///
/// 使用方式：
/// ```dart
/// // 初始化（全局只需一次）
/// await MiniMaxSpeechService.instance.initialize('your-api-key');
///
/// // 开始合成
/// final taskId = MiniMaxSpeechService.instance.synthesize(
///   text: '你好，这是测试',
///   voiceId: 'female-yujie',
///   onChunk: (chunk) { /* 处理音频片段 */ },
///   onStateChanged: (state) { /* 处理状态变化 */ },
/// );
///
/// // 查询状态
/// final info = MiniMaxSpeechService.instance.queryTaskInfo(taskId);
///
/// // 中断任务
/// await MiniMaxSpeechService.instance.interrupt(taskId);
/// ```
class MiniMaxSpeechService {
  MiniMaxSpeechService._();

  static final MiniMaxSpeechService instance = MiniMaxSpeechService._();

  final Uuid _uuid = const Uuid();

  String? _apiKey;
  bool _initialized = false;

  // 活跃的任务 <taskId, task>
  final Map<String, _SpeechTask> _tasks = {};

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 获取所有任务ID
  List<String> get taskIds => _tasks.keys.toList();

  /// 初始化服务（建议在 main.dart 中调用一次）
  Future<void> initialize(String apiKey) async {
    _apiKey = apiKey;
    _initialized = true;
  }

  /// 开始流式语音合成
  ///
  /// [text] 要合成的文本
  /// [voiceId] 音色ID，默认 female-yujie
  /// [model] 模型，默认 speech-2.8-hd
  /// [speed] 语速，默认 1.0
  /// [vol] 音量，默认 1.0
  /// [pitch] 音调，默认 0
  /// [sampleRate] 采样率，默认 32000
  /// [bitrate] 比特率，默认 128000
  /// [format] 格式，默认 mp3
  /// [channel] 声道，默认 1（单声道）
  /// [englishNormalization] 英文正则化，默认 false
  /// [onChunk] 音频片段回调（每个chunk到达时触发）
  /// [onStateChanged] 状态变化回调
  ///
  /// 返回 taskId，用于后续的状态控制和查询
  Future<String> synthesize({
    required String text,
    String voiceId = 'female-yujie',
    String model = 'speech-2.8-hd',
    double speed = 1.0,
    double vol = 1.0,
    double pitch = 0,
    int sampleRate = 32000,
    int bitrate = 128000,
    String format = 'mp3',
    int channel = 1,
    bool englishNormalization = false,
    void Function(Uint8List chunk)? onChunk,
    void Function(TaskState state)? onStateChanged,
  }) async {
    _ensureInitialized();

    final taskId = _uuid.v4();
    final params = SynthesisParams(
      text: text,
      voiceId: voiceId,
      model: model,
      speed: speed,
      vol: vol,
      pitch: pitch,
      sampleRate: sampleRate,
      bitrate: bitrate,
      format: format,
      channel: channel,
      englishNormalization: englishNormalization,
      onChunk: onChunk,
      onStateChanged: onStateChanged,
    );
    final task = _SpeechTask(taskId, params);
    _tasks[taskId] = task;

    // 异步执行，不阻塞
    _runSynthesis(task);

    return taskId;
  }

  /// 查询任务状态
  TaskState queryState(String taskId) {
    final task = _tasks[taskId];
    return task?._state ?? TaskState.idle;
  }

  /// 查询已收集的音频数据
  List<int> queryChunks(String taskId) {
    final task = _tasks[taskId];
    return task != null ? List<int>.from(task._collectedChunks) : [];
  }

  /// 查询任务信息
  SynthesisTaskInfo? queryTaskInfo(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return null;
    return SynthesisTaskInfo(
      taskId: taskId,
      state: task._state,
      text: task._params.text,
      voiceId: task._params.voiceId,
      chunkCount: task._chunkCount,
      totalBytes: task._totalBytes,
      errorMessage: task._errorMessage,
      startTime: task._startTime,
    );
  }

  /// 中断指定任务
  Future<void> interrupt(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    task._close();
  }

  /// 中断所有任务
  Future<void> interruptAll() async {
    for (final taskId in _tasks.keys.toList()) {
      await interrupt(taskId);
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await interruptAll();
    _tasks.clear();
    _initialized = false;
    _apiKey = null;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MiniMaxSpeechService 未初始化，请先调用 initialize(apiKey)');
    }
  }

  Future<void> _runSynthesis(_SpeechTask task) async {
    task._start();

    WebSocketChannel? channel;
    StreamSubscription? subscription;
    StreamController<dynamic>? controller;

    try {
      final uri = Uri.parse('wss://api.minimaxi.com/ws/v1/t2a_v2');
      channel = WebSocketChannel.connect(
        uri,
        protocols: ['Authorization', 'Bearer $_apiKey'],
      );
      task._channel = channel;

      final broadcastController = StreamController<dynamic>.broadcast();
      controller = broadcastController;
      subscription = channel.stream.listen(
        (data) {
          if (!broadcastController.isClosed) broadcastController.add(data);
        },
        onError: (e) {
          if (!broadcastController.isClosed) broadcastController.addError(e);
        },
        onDone: () {
          if (!broadcastController.isClosed) broadcastController.close();
        },
      );

      final iterator = StreamIterator(broadcastController.stream);

      // 等待连接确认
      if (!await iterator.moveNext()) {
        task._setError('连接被关闭');
        return;
      }
      final welcome =
          json.decode(iterator.current as String) as Map<String, dynamic>;
      if (welcome['event'] != 'connected_success') {
        task._setError('连接失败: ${iterator.current}');
        return;
      }

      // 发送 task_start
      final voiceSetting = <String, dynamic>{
        'voice_id': task._params.voiceId,
        'speed': _normalizeNumeric(task._params.speed),
        'vol': _normalizeNumeric(task._params.vol),
        'pitch': task._params.pitch.toInt(),
      };
      final audioSetting = <String, dynamic>{
        'sample_rate': task._params.sampleRate,
        'bitrate': task._params.bitrate,
        'format': task._params.format,
        'channel': task._params.channel,
      };
      channel.sink.add(
        json.encode({
          'event': 'task_start',
          'model': task._params.model,
          'language_boost': task._params.englishNormalization
              ? 'English'
              : 'Chinese',
          'voice_setting': voiceSetting,
          'audio_setting': audioSetting,
        }),
      );

      // 等待 task_started
      if (!await iterator.moveNext()) {
        task._setError('连接被关闭');
        return;
      }
      final startResp =
          json.decode(iterator.current as String) as Map<String, dynamic>;
      if (startResp['event'] != 'task_started') {
        task._setError('任务启动失败: ${iterator.current}');
        return;
      }

      // 发送文本
      channel.sink.add(
        json.encode({'event': 'task_continue', 'text': task._params.text}),
      );
      channel.sink.add(json.encode({'event': 'task_finish'}));

      task._updateState(TaskState.synthesizing);

      // 持续读取音频数据
      while (await iterator.moveNext()) {
        if (task._isClosed) break;

        final data = iterator.current;
        List<int>? audioBytes;

        if (data is List<int>) {
          audioBytes = data;
        } else {
          try {
            final message = json.decode(data as String) as Map<String, dynamic>;
            final event = message['event'] as String?;

            if (message['data'] != null && message['data']['audio'] != null) {
              final audioHex = message['data']['audio'] as String;
              if (audioHex.isNotEmpty) {
                audioBytes = _hexToBytes(audioHex);
              }
            }

            if (event == 'task_finished') {
              task._updateState(TaskState.finished);
              break;
            } else if (event == 'task_failed') {
              task._setError(message['base_resp']?['status_msg'] ?? '未知错误');
              break;
            }
          } catch (_) {
            // 忽略解析错误
          }
        }

        if (audioBytes != null && !task._isClosed) {
          task._addChunk(audioBytes);
        }
      }
    } catch (e) {
      task._setError(e.toString());
    } finally {
      await subscription?.cancel();
      await channel?.sink.close();
      await controller?.close();
      task._channel = null;
    }
  }

  int _normalizeNumeric(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt();
    }
    return double.parse(value.toStringAsFixed(2)).toInt();
  }

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}

/// 合成参数
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
  final void Function(Uint8List chunk)? onChunk;
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

/// 任务状态
enum TaskState {
  /// 空闲/未找到
  idle,

  /// 正在连接
  connecting,

  /// 正在合成（流式传输中）
  synthesizing,

  /// 已完成
  finished,

  /// 出错
  error,

  /// 被中断
  interrupted,
}

/// 任务信息（只读快照）
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

/// 内部任务状态管理
class _SpeechTask {
  final String id;
  final SynthesisParams _params;

  TaskState _state = TaskState.idle;
  WebSocketChannel? _channel;
  int _chunkCount = 0;
  int _totalBytes = 0;
  final List<int> _collectedChunks = [];
  String? _errorMessage;
  DateTime? _startTime;
  bool _closed = false;

  _SpeechTask(this.id, this._params);

  bool get _isClosed => _closed;

  void _start() {
    _startTime = DateTime.now();
    _updateState(TaskState.connecting);
  }

  void _updateState(TaskState newState) {
    _state = newState;
    _params.onStateChanged?.call(newState);
  }

  void _addChunk(List<int> chunk) {
    _chunkCount++;
    _totalBytes += chunk.length;
    _collectedChunks.addAll(chunk);
    _params.onChunk?.call(Uint8List.fromList(chunk));
  }

  void _setError(String message) {
    _errorMessage = message;
    _updateState(TaskState.error);
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _channel?.sink.close();
    _updateState(TaskState.interrupted);
  }
}
