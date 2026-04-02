import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
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

  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<int> _audioChunks = [];

  // 常用中文音色
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

  // 常用英文音色
  static const _englishVoices = [
    ('Arnold', 'Arnold'),
    ('Sweet_Girl', 'Sweet Girl'),
    ('Charming_Lady', 'Charming Lady'),
    ('English_Trustworthy_Man', 'Trustworthy Man'),
  ];

  // 可选模型
  static const _models = [
    ('speech-2.8-hd', 'speech-2.8-hd (高清)'),
    ('speech-2.6-hd', 'speech-2.6-hd (高清低延迟)'),
    ('speech-2.8-turbo', 'speech-2.8-turbo (快速)'),
    ('speech-02-hd', 'speech-02-hd (优质)'),
    ('speech-02-turbo', 'speech-02-turbo (快速)'),
  ];

  // 采样率选项
  static const _sampleRates = [16000, 32000, 48000];

  // 比特率选项
  static const _bitrates = [64000, 128000, 192000, 256000];

  // 音频格式选项
  static const _formats = ['mp3', 'wav', 'pcm'];

  // 声道选项
  static const _channels = [1, 2];

  // 测试文本
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
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerComplete.listen((_) {
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
    _audioPlayer.dispose();
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
      _statusMessage = '正在连接...';
      _audioChunks.clear();
    });

    try {
      final ws = WebSocketChannel.connect(
        Uri.parse('wss://api.minimaxi.com/ws/v1/t2a_v2'),
        protocols: ['Bearer ${_apiKeyController.text}'],
      );

      setState(() {
        _isConnected = true;
        _statusMessage = '已连接，正在合成...';
      });

      // 发送开始请求
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

      // 等待任务开始
      final firstData = await ws.stream.first;
      final firstResponse = json.decode(firstData as String);
      if (firstResponse['event'] != 'task_started') {
        ws.sink.close();
        throw Exception('任务启动失败: ${firstResponse['event']}');
      }

      // 发送文本
      ws.sink.add(json.encode({
        'event': 'task_continue',
        'text': text,
      }));

      // 监听音频数据
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
          _playAudio();
          ws.sink.close();
        }
      }, onError: (error) {
        setState(() {
          _statusMessage = '错误: $error';
          _isConnected = false;
        });
      }, onDone: () {
        if (_audioChunks.isEmpty) {
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

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  Future<void> _playAudio() async {
    if (_audioChunks.isEmpty) return;

    setState(() => _isPlaying = true);

    try {
      final audioData = Uint8List.fromList(_audioChunks);
      await _audioPlayer.play(UrlSource('data:audio/mp3;base64,${base64Encode(audioData)}'));
      setState(() => _statusMessage = '正在播放...');
    } catch (e) {
      setState(() {
        _statusMessage = '播放失败: $e';
        _isPlaying = false;
      });
    }
  }

  void _stopAudio() {
    _audioPlayer.stop();
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
                      // 速度
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
                      // 音量
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
                      // 音调
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
                      // 英文正则化
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
                      // 采样率
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
                      // 比特率
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
                      // 格式
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
                      // 声道
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
