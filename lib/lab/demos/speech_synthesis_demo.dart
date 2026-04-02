import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../lab_container.dart';

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
  bool _isConnected = false;
  bool _showAdvanced = false;
  bool _streamingMode = false;

  // 流式播放相关（仅非Web平台）
  HttpServer? _streamingServer;
  final List<IOSink> _streamSinks = [];
  final List<int> _audioChunks = [];
  bool _streamingStarted = false;
  int _receivedChunks = 0;

  // 收集模式播放器
  final AudioPlayer _collectPlayer = AudioPlayer();
  // 流式模式播放器
  ja.AudioPlayer? _streamingPlayer;

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

  WebSocketChannel? _ws;
  StreamSubscription? _wsSubscription;

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
    _setupCollectPlayer();
    if (!kIsWeb) {
      _streamingPlayer = ja.AudioPlayer();
    }
  }

  void _setupCollectPlayer() {
    _collectPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _statusMessage = '播放完成';
        });
      }
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _textController.dispose();
    _customModelController.dispose();
    _wsSubscription?.cancel();
    _ws?.sink.close();
    _stopStreamingServer();
    _collectPlayer.dispose();
    _streamingPlayer?.dispose();
    super.dispose();
  }

  Future<void> _stopStreamingServer() async {
    for (final sink in _streamSinks) {
      await sink.close();
    }
    _streamSinks.clear();
    await _streamingServer?.close(force: true);
    _streamingServer = null;
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
      _statusMessage = '正在连接...';
      _audioChunks.clear();
      _receivedChunks = 0;
      _streamingStarted = false;
    });

    if (_streamingMode && !kIsWeb) {
      await _synthesizeStreaming(model, text);
    } else {
      await _synthesizeCollect(model, text);
    }
  }

  /// 收集模式（原有逻辑）
  Future<void> _synthesizeCollect(String model, String text) async {
    try {
      final ws = WebSocketChannel.connect(
        Uri.parse('wss://api.minimaxi.com/ws/v1/t2a_v2'),
        protocols: ['Bearer ${_apiKeyController.text}'],
      );

      setState(() {
        _isConnected = true;
        _statusMessage = '已连接，正在合成...';
      });

      ws.sink.add(json.encode({
        'event': 'task_start',
        'model': model,
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
      }));

      final firstData = await ws.stream.first;
      final firstResponse = json.decode(firstData as String);
      if (firstResponse['event'] != 'task_started') {
        ws.sink.close();
        throw Exception('任务启动失败: ${firstResponse['event']}');
      }

      ws.sink.add(json.encode({
        'event': 'task_continue',
        'text': text,
      }));

      ws.stream.listen((data) {
        final response = json.decode(data as String);
        if (response['data'] != null && response['data']['audio'] != null) {
          final audioHex = response['data']['audio'] as String;
          if (audioHex.isNotEmpty) {
            final audioBytes = _hexToBytes(audioHex);
            _audioChunks.addAll(audioBytes);
          }
        }
        if (response['is_final'] == true) {
          _playCollectAudio();
          ws.sink.close();
        }
      }, onError: (error) {
        setState(() {
          _statusMessage = '错误: $error';
          _isConnected = false;
        });
      }, onDone: () {
        if (_audioChunks.isEmpty && !_isPlaying) {
          setState(() {
            _statusMessage = '未收到音频数据';
            _isConnected = false;
          });
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = '连接失败: $e';
        _isConnected = false;
      });
    }
  }

  /// 流式模式 - 使用本地 HTTP 服务器 + just_audio
  Future<void> _synthesizeStreaming(String model, String text) async {
    if (kIsWeb) {
      setState(() => _statusMessage = '流式模式仅支持安卓/iOS');
      return;
    }

    try {
      // 先停止之前的服务器
      await _stopStreamingServer();

      // 启动本地 HTTP 服务器用于流式传输
      _streamingServer = await HttpServer.bind('127.0.0.1', 0);
      final port = _streamingServer!.port;

      // 监听请求，当播放器请求时提供流式数据
      _streamingServer!.listen((request) async {
        if (request.uri.path == '/audio') {
          final response = request.response;
          response.headers.set('Content-Type', 'audio/mpeg');
          response.headers.set('Accept-Ranges', 'none');
          response.headers.set('Cache-Control', 'no-cache');

          final sink = IOSink(response);
          _streamSinks.add(sink);

          // 如果已有数据，先发送已有的
          if (_audioChunks.isNotEmpty) {
            sink.add(Uint8List.fromList(_audioChunks));
          }
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });

      // 连接 WebSocket
      _ws = WebSocketChannel.connect(
        Uri.parse('wss://api.minimaxi.com/ws/v1/t2a_v2'),
        protocols: ['Bearer ${_apiKeyController.text}'],
      );

      setState(() {
        _isConnected = true;
        _statusMessage = '已连接，正在合成...';
      });

      _ws!.sink.add(json.encode({
        'event': 'task_start',
        'model': model,
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
      }));

      final firstData = await _ws!.stream.first;
      final firstResponse = json.decode(firstData as String);
      if (firstResponse['event'] != 'task_started') {
        _ws!.sink.close();
        throw Exception('任务启动失败: ${firstResponse['event']}');
      }

      _ws!.sink.add(json.encode({
        'event': 'task_continue',
        'text': text,
      }));

      _wsSubscription = _ws!.stream.listen(
        (data) {
          final response = json.decode(data as String);
          if (response['data'] != null && response['data']['audio'] != null) {
            final audioHex = response['data']['audio'] as String;
            if (audioHex.isNotEmpty) {
              final audioBytes = _hexToBytes(audioHex);
              _audioChunks.addAll(audioBytes);
              _receivedChunks++;

              // 边收边播：发送给所有连接的客户端
              for (final sink in _streamSinks) {
                sink.add(audioBytes);
              }

              // 首次收到数据时启动播放器
              if (!_streamingStarted && _audioChunks.length >= 5000) {
                _startStreamingPlayback('http://127.0.0.1:$port/audio');
              }

              setState(() {
                _statusMessage = '流式接收中... ($_receivedChunks chunks)';
              });
            }
          }
          if (response['is_final'] == true) {
            _ws!.sink.close();
            setState(() {
              _statusMessage = '流式接收完成，共 ${_receivedChunks} chunks';
            });
          }
        },
        onError: (error) {
          setState(() {
            _statusMessage = '错误: $error';
            _isConnected = false;
          });
        },
        onDone: () {
          _wsSubscription?.cancel();
          _ws = null;
          if (_audioChunks.isEmpty && !_isPlaying) {
            setState(() {
              _statusMessage = '未收到音频数据';
              _isConnected = false;
            });
          }
        },
      );
    } catch (e) {
      await _stopStreamingServer();
      setState(() {
        _statusMessage = '连接失败: $e';
        _isConnected = false;
      });
    }
  }

  /// 开始流式播放
  Future<void> _startStreamingPlayback(String url) async {
    if (_streamingStarted || _streamingPlayer == null) return;
    _streamingStarted = true;

    try {
      await _streamingPlayer!.setUrl(url);
      await _streamingPlayer!.play();
      setState(() => _isPlaying = true);
    } catch (e) {
      _streamingStarted = false;
      setState(() => _statusMessage = '流式播放失败，将使用收集模式: $e');
    }
  }

  /// 收集模式播放
  Future<void> _playCollectAudio() async {
    if (_audioChunks.isEmpty) return;

    setState(() => _isPlaying = true);

    try {
      final audioData = Uint8List.fromList(_audioChunks);
      await _collectPlayer.play(UrlSource('data:audio/mp3;base64,${base64Encode(audioData)}'));
      setState(() => _statusMessage = '正在播放...');
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
    _collectPlayer.stop();
    _streamingPlayer?.stop();
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

            // 流式模式开关
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('流式播放模式 (just_audio)'),
                      subtitle: Text(
                        _streamingMode
                            ? '本地HTTP服务器流式边收边播（仅安卓/iOS）'
                            : '收完后统一播放（稳定推荐）',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _streamingMode,
                      onChanged: (v) => setState(() => _streamingMode = v),
                      contentPadding: EdgeInsets.zero,
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
                    if (_isConnected || _isPlaying)
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

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isPlaying || _isConnected) ? null : _synthesize,
                    icon: Icon(_streamingMode ? Icons.stream : Icons.play_arrow),
                    label: Text(_streamingMode ? '流式合成播放' : '合成并播放'),
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
