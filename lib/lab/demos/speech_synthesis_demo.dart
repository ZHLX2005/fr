import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../lab_container.dart';

/// 由 WebSocket 音频数据驱动的流式 AudioSource
/// 用广播 StreamController 分发数据，每次 request() 创建新订阅
class _WebSocketAudioSource extends StreamAudioSource {
  // 广播流：所有 chunk 都通过这里分发
  final StreamController<List<int>> _broadcast = StreamController<List<int>>.broadcast();
  final List<int> _buffer = []; // 已接收的全部数据（用于支持 seek）
  bool _closed = false;
  int _totalBytes = 0;

  /// 追加一个音频 chunk
  void addChunk(List<int> bytes) {
    if (_closed) return;
    _totalBytes += bytes.length;
    _buffer.addAll(bytes);
    _broadcast.add(bytes);
  }

  /// 标记音频数据传输完成
  void markComplete() {
    if (_closed) return;
    _closed = true;
    _broadcast.close();
  }

  int get totalBytes => _totalBytes;
  bool get isClosed => _closed;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;

    // 如果还没收到数据，等待第一个 chunk
    while (_totalBytes == 0 && !_closed) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (_totalBytes == 0) {
      return StreamAudioResponse(
        sourceLength: 0,
        contentLength: 0,
        offset: 0,
        stream: const Stream.empty(),
        contentType: 'audio/mpeg',
      );
    }

    end ??= _totalBytes;

    // 已缓冲的数据：从 start 到当前已有数据的末尾
    final bufferedEnd = _buffer.length;
    final dataEnd = end > bufferedEnd ? bufferedEnd : end;
    final initialData = start < dataEnd
        ? Uint8List.fromList(_buffer.sublist(start, dataEnd))
        : Uint8List(0);

    // 构建输出流：已有数据 + 后续新增数据的广播订阅
    final outputController = StreamController<List<int>>();

    // 发送已有数据
    if (initialData.isNotEmpty) {
      outputController.add(initialData);
    }

    // 如果已关闭，直接结束
    if (_closed) {
      await outputController.close();
    } else {
      // 订阅广播流，转发新增数据
      final subscription = _broadcast.stream.listen(
        (chunk) {
          if (outputController.isClosed) return;
          outputController.add(chunk);
        },
        onDone: () async {
          if (!outputController.isClosed) await outputController.close();
        },
        onError: (e) async {
          if (!outputController.isClosed) await outputController.close();
        },
      );

      // 当输出流被消费者取消时，取消广播订阅
      outputController.onCancel = () {
        subscription.cancel();
      };
    }

    return StreamAudioResponse(
      sourceLength: _closed ? _buffer.length : 0x7FFFFFFF,
      contentLength: _closed ? (_buffer.length - start) : 0x7FFFFFFF,
      offset: start,
      stream: outputController.stream,
      contentType: 'audio/mpeg',
    );
  }
}

/// 语音合成 Demo
class SpeechSynthesisDemo extends DemoPage {
  @override
  String get title => '语音合成';

  @override
  String get description => 'MiniMax 语音合成测试';

  @override
  Widget buildPage(BuildContext context) {
    return const _SpeechSynthesisPage();
  }
}

class _SpeechSynthesisPage extends StatefulWidget {
  const _SpeechSynthesisPage();

  @override
  State<_SpeechSynthesisPage> createState() => _SpeechSynthesisPageState();
}

class _SpeechSynthesisPageState extends State<_SpeechSynthesisPage> {
  final _apiKeyController = TextEditingController();
  final _textController = TextEditingController();
  final _customModelController = TextEditingController();

  String? _selectedVoiceId;
  String? _selectedVoiceName;
  String? _statusMessage;
  bool _isPlaying = false;
  bool _showAdvanced = false;
  bool _useStreaming = true;

  // HTTP 方式音频数据
  final List<int> _audioChunks = [];

  // WebSocket 流式播放
  WebSocket? _ws;
  bool _isSynthesizing = false;
  int _chunkCount = 0;
  _WebSocketAudioSource? _streamSource;

  // 播放器
  final AudioPlayer _player = AudioPlayer();

  // 高级设置
  String _selectedModel = 'speech-2.8-hd';
  double _speed = 1.0;
  double _vol = 1.0;
  double _pitch = 0;
  bool _englishNormalization = false;
  int _sampleRate = 32000;
  int _bitrate = 128000;
  String _format = 'mp3';
  int _channel = 1;

  static const _chineseVoices = [
    ('male-qn-qingse', '青涩青年'),
    ('male-qn-jingying', '精英青年'),
    ('male-qn-badao', '霸道青年'),
    ('female-shaonv', '少女'),
    ('female-yujie', '御姐'),
    ('female-tianmei', '甜美女性'),
    ('Chinese (Mandarin)_News_Anchor', '新闻女声'),
    ('Chinese (Mandarin)_Gentleman', '温润男声'),
  ];

  static const _englishVoices = [
    ('Arnold', 'Arnold'),
    ('Sweet_Girl', 'Sweet Girl'),
    ('Charming_Lady', 'Charming Lady'),
    ('English_Trustworthy_Man', 'Trustworthy Man'),
  ];

  static const _models = [
    ('speech-2.8-hd', 'speech-2.8-hd (高清)'),
    ('speech-2.6-hd', 'speech-2.6-hd (高清低延迟)'),
    ('speech-2.8-turbo', 'speech-2.8-turbo (快速)'),
    ('speech-02-hd', 'speech-02-hd (优质)'),
    ('speech-02-turbo', 'speech-02-turbo (快速)'),
  ];

  static const _sampleRates = [16000, 32000, 48000];
  static const _bitrates = [64000, 128000, 192000, 256000];
  static const _formats = ['mp3', 'wav', 'pcm'];
  static const _channels = [1, 2];

  static const _testTexts = [
    '你好，这是一段语音合成测试文本。',
    'Hello, this is a speech synthesis test.',
    '真正的危险不是计算机开始像人一样思考，而是人开始像计算机一样思考。',
    'The only limit to our realization of tomorrow will be our doubts of today.',
  ];

  @override
  void initState() {
    super.initState();
    _customModelController.text = _selectedModel;
    _setupPlayer();
  }

  void _setupPlayer() {
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _statusMessage = '播放完成';
            _isPlaying = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _streamSource?.markComplete();
    _ws?.close();
    _apiKeyController.dispose();
    _textController.dispose();
    _customModelController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _synthesize() async {
    if (_apiKeyController.text.isEmpty) {
      setState(() => _statusMessage = '请输入 API Key');
      return;
    }
    if (_selectedVoiceId == null) {
      setState(() => _statusMessage = '请选择音色');
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = '请输入要合成的文本');
      return;
    }

    final model = _customModelController.text.trim().isEmpty
        ? _selectedModel
        : _customModelController.text.trim();

    setState(() {
      _statusMessage = '正在合成...';
      _audioChunks.clear();
    });

    if (_useStreaming) {
      await _synthesizeWebSocket(model, text);
    } else {
      await _synthesizeHttp(model, text);
    }
  }

  /// 关闭已有的 WebSocket 连接
  Future<void> _closeExistingConnection() async {
    _streamSource?.markComplete();
    _streamSource = null;
    await _ws?.close();
    _ws = null;
    _isSynthesizing = false;
    _chunkCount = 0;
  }

  /// WebSocket 流式合成：边接收边通过 StreamAudioSource 播放
  Future<void> _synthesizeWebSocket(String model, String text) async {
    if (_isSynthesizing) {
      await _closeExistingConnection();
    }

    try {
      _isSynthesizing = true;
      _chunkCount = 0;

      // 创建流式数据源
      _streamSource = _WebSocketAudioSource();

      _ws = await WebSocket.connect(
        'wss://api.minimaxi.com/ws/v1/t2a_v2',
        headers: {'Authorization': 'Bearer ${_apiKeyController.text}'},
      );

      setState(() => _statusMessage = '正在连接...');

      final iterator = StreamIterator(_ws!);

      // 等待连接确认
      if (!await iterator.moveNext()) {
        _isSynthesizing = false;
        setState(() => _statusMessage = '连接被关闭');
        return;
      }
      final welcome = json.decode(iterator.current as String) as Map<String, dynamic>;
      if (welcome['event'] != 'connected_success') {
        await _ws!.close();
        _isSynthesizing = false;
        setState(() => _statusMessage = '连接失败: ${iterator.current}');
        return;
      }

      // 发送 task_start
      final voiceSetting = <String, dynamic>{
        'voice_id': _selectedVoiceId,
        'speed': _speed == _speed.roundToDouble() ? _speed.toInt() : _speed,
        'vol': _vol == _vol.roundToDouble() ? _vol.toInt() : _vol,
        'pitch': _pitch.toInt(),
      };
      final audioSetting = <String, dynamic>{
        'sample_rate': _sampleRate,
        'bitrate': _bitrate,
        'format': _format,
        'channel': _channel,
      };
      _ws!.add(json.encode({
        'event': 'task_start',
        'model': model,
        'language_boost': _englishNormalization ? 'English' : 'Chinese',
        'voice_setting': voiceSetting,
        'audio_setting': audioSetting,
      }));

      // 等待 task_started
      if (!await iterator.moveNext()) {
        _isSynthesizing = false;
        setState(() => _statusMessage = '连接被关闭');
        return;
      }
      final startResp = json.decode(iterator.current as String) as Map<String, dynamic>;
      if (startResp['event'] != 'task_started') {
        await _ws!.close();
        _isSynthesizing = false;
        setState(() => _statusMessage = '任务启动失败: ${iterator.current}');
        return;
      }

      // 发送文本 + 结束标记
      _ws!.add(json.encode({'event': 'task_continue', 'text': text}));
      _ws!.add(json.encode({'event': 'task_finish'}));

      setState(() => _statusMessage = '流式合成中...');

      // 开始播放（不 await，让播放和接收并行）
      _startStreamPlayback();

      // 持续读取，将音频 chunk 推入 stream source
      while (await iterator.moveNext()) {
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
              if (audioHex.isNotEmpty) audioBytes = _hexToBytes(audioHex);
            }

            if (event == 'task_finished') {
              _isSynthesizing = false;
              _streamSource?.markComplete();
              break;
            } else if (event == 'task_failed') {
              _isSynthesizing = false;
              _streamSource?.markComplete();
              setState(() => _statusMessage = '合成失败: ${message['base_resp']?['status_msg'] ?? '未知错误'}');
              return;
            }
          } catch (e) {
            // 忽略解析错误
          }
        }

        // 推入流式数据源
        if (audioBytes != null) {
          _chunkCount++;
          _streamSource?.addChunk(audioBytes);
          setState(() {
            _statusMessage = '流式接收中... 已接收 $_chunkCount 个片段 (${_streamSource!.totalBytes ~/ 1024}KB)';
          });
        }
      }

      _isSynthesizing = false;
      setState(() {
        _statusMessage = '流式合成完成，共 $_chunkCount 个片段 (${_streamSource!.totalBytes ~/ 1024}KB)';
      });
    } catch (e) {
      _isSynthesizing = false;
      _streamSource?.markComplete();
      setState(() => _statusMessage = '流式合成异常: $e');
    }
  }

  /// 开始流式播放（不阻塞）
  void _startStreamPlayback() {
    setState(() {
      _isPlaying = true;
      _statusMessage = '正在播放流式音频...';
    });

    _player.setAudioSource(_streamSource!).then((_) {
      _player.play();
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _statusMessage = '播放失败: $e';
          _isPlaying = false;
        });
      }
    });
  }

  /// HTTP API 合成
  Future<void> _synthesizeHttp(String model, String text) async {
    try {
      final uri = Uri.parse('https://api.minimaxi.com/v1/t2a_v2');
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(uri);

      request.headers.set('Authorization', 'Bearer ${_apiKeyController.text}');
      request.headers.set('Content-Type', 'application/json');

      final requestBody = json.encode({
        'model': model,
        'text': text,
        'stream': false,
        'voice_setting': {
          'voice_id': _selectedVoiceId,
          'speed': _speed,
          'vol': _vol,
          'pitch': _pitch,
          'english_normalization': _englishNormalization,
        },
        'audio_setting': {
          'sample_rate': _sampleRate,
          'bitrate': _bitrate,
          'format': _format,
          'channel': _channel,
        },
      });

      request.write(requestBody);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final responseData = json.decode(responseBody);
        if (responseData['data'] != null && responseData['data']['audio'] != null) {
          final audioHex = responseData['data']['audio'] as String;
          final audioBytes = _hexToBytes(audioHex);
          _audioChunks.addAll(audioBytes);
          setState(() => _statusMessage = '合成完成，音频大小: ${audioBytes.length} bytes');
          await _playAudio();
        } else {
          setState(() => _statusMessage = '响应格式错误: $responseData');
        }
      } else {
        setState(() => _statusMessage = '请求失败: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      setState(() => _statusMessage = '请求异常: $e');
    }
  }

  /// 播放音频 (HTTP 方式)
  Future<void> _playAudio() async {
    if (_audioChunks.isEmpty) return;

    setState(() {
      _isPlaying = true;
      _statusMessage = '正在播放...';
    });

    try {
      final audioData = Uint8List.fromList(_audioChunks);
      final source = AudioSource.uri(
        Uri.dataFromBytes(audioData, mimeType: 'audio/mpeg'),
      );
      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      setState(() {
        _statusMessage = '播放失败: $e';
        _isPlaying = false;
      });
    }
  }

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  void _stopAudio() {
    _player.stop();
    _streamSource?.markComplete();
    _streamSource = null;
    setState(() {
      _isPlaying = false;
      _statusMessage = '已停止';
    });
  }

  void _selectVoice(String id, String name) {
    setState(() {
      _selectedVoiceId = id;
      _selectedVoiceName = name;
    });
  }

  void _useTestText(int index) {
    _textController.text = _testTexts[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.record_voice_over, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'MiniMax 语音合成',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // API Key 输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('API Key', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        hintText: '输入您的 API Key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 模型选择
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('选择模型', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                          icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                          label: Text(_showAdvanced ? '收起高级设置' : '高级设置'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedModel,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _models.map((m) => DropdownMenuItem(
                        value: m.$1,
                        child: Text(m.$2),
                      )).toList(),
                      onChanged: (v) => setState(() {
                        _selectedModel = v!;
                        _customModelController.text = v;
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customModelController,
                      decoration: const InputDecoration(
                        labelText: '或输入自定义模型',
                        hintText: '如: speech-2.8-hd',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _selectedModel = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 高级设置
            if (_showAdvanced) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('语音设置', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('速度')),
                          Expanded(
                            child: Slider(
                              value: _speed,
                              min: 0.5,
                              max: 2.0,
                              divisions: 15,
                              label: _speed.toStringAsFixed(1),
                              onChanged: (v) => setState(() => _speed = v),
                            ),
                          ),
                          SizedBox(width: 50, child: Text(_speed.toStringAsFixed(1))),
                        ],
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('音量')),
                          Expanded(
                            child: Slider(
                              value: _vol,
                              min: 0.1,
                              max: 2.0,
                              divisions: 19,
                              label: _vol.toStringAsFixed(1),
                              onChanged: (v) => setState(() => _vol = v),
                            ),
                          ),
                          SizedBox(width: 50, child: Text(_vol.toStringAsFixed(1))),
                        ],
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('音调')),
                          Expanded(
                            child: Slider(
                              value: _pitch,
                              min: -10,
                              max: 10,
                              divisions: 20,
                              label: _pitch.toStringAsFixed(0),
                              onChanged: (v) => setState(() => _pitch = v),
                            ),
                          ),
                          SizedBox(width: 50, child: Text(_pitch.toStringAsFixed(0))),
                        ],
                      ),
                      SwitchListTile(
                        title: const Text('英文正则化'),
                        value: _englishNormalization,
                        onChanged: (v) => setState(() => _englishNormalization = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('音频设置', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('采样率')),
                          Expanded(
                            child: SegmentedButton<int>(
                              segments: _sampleRates.map((r) => ButtonSegment(
                                value: r,
                                label: Text('${r ~/ 1000}k'),
                              )).toList(),
                              selected: {_sampleRate},
                              onSelectionChanged: (s) => setState(() => _sampleRate = s.first),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('比特率')),
                          Expanded(
                            child: SegmentedButton<int>(
                              segments: _bitrates.map((r) => ButtonSegment(
                                value: r,
                                label: Text('${r ~/ 1000}k'),
                              )).toList(),
                              selected: {_bitrate},
                              onSelectionChanged: (s) => setState(() => _bitrate = s.first),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('格式')),
                          SegmentedButton<String>(
                            segments: _formats.map((f) => ButtonSegment(
                              value: f,
                              label: Text(f.toUpperCase()),
                            )).toList(),
                            selected: {_format},
                            onSelectionChanged: (s) => setState(() => _format = s.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('声道')),
                          SegmentedButton<int>(
                            segments: _channels.map((c) => ButtonSegment(
                              value: c,
                              label: Text(c == 1 ? '单声道' : '立体声'),
                            )).toList(),
                            selected: {_channel},
                            onSelectionChanged: (s) => setState(() => _channel = s.first),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 音色选择
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择音色', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('中文音色', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _chineseVoices.map((v) {
                        final isSelected = _selectedVoiceId == v.$1;
                        return ChoiceChip(
                          label: Text(v.$2),
                          selected: isSelected,
                          onSelected: (_) => _selectVoice(v.$1, v.$2),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('英文音色', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _englishVoices.map((v) {
                        final isSelected = _selectedVoiceId == v.$1;
                        return ChoiceChip(
                          label: Text(v.$2),
                          selected: isSelected,
                          onSelected: (_) => _selectVoice(v.$1, v.$2),
                        );
                      }).toList(),
                    ),
                    if (_selectedVoiceName != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Text(
                          '已选择: $_selectedVoiceName',
                          style: TextStyle(color: Colors.green[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 文本输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('合成文本', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '输入要合成的文本',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('快速测试文本', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_testTexts.length, (i) {
                        return ActionChip(
                          label: Text(
                            _testTexts[i].length > 15
                                ? '${_testTexts[i].substring(0, 15)}...'
                                : _testTexts[i],
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => _useTestText(i),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 状态显示
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage!.contains('失败') || _statusMessage!.contains('错误')
                      ? Colors.red[50]
                      : _statusMessage!.contains('流式')
                          ? Colors.orange[50]
                          : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (_isPlaying)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _statusMessage!.contains('失败') || _statusMessage!.contains('错误')
                            ? Icons.error_outline
                            : Icons.info_outline,
                        size: 16,
                        color: Colors.grey,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusMessage!.contains('失败') || _statusMessage!.contains('错误')
                              ? Colors.red[700]
                              : Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // 流式输出开关
            Card(
              child: SwitchListTile(
                title: const Text('流式输出'),
                subtitle: Text(_useStreaming ? 'WebSocket 边合成边播放' : 'HTTP 等待合成完成后再播放'),
                value: _useStreaming,
                onChanged: (v) => setState(() => _useStreaming = v),
                secondary: Icon(
                  _useStreaming ? Icons.stream : Icons.cloud_download,
                  color: _useStreaming ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPlaying ? null : _synthesize,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('合成并播放'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isPlaying ? _stopAudio : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void registerSpeechSynthesisDemo() {
  demoRegistry.register(SpeechSynthesisDemo());
}
