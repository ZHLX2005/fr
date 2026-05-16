import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 由 WebSocket 音频数据驱动的流式 AudioSource
class _WebSocketAudioSource extends StreamAudioSource {
  final StreamController<List<int>> _broadcast =
      StreamController<List<int>>.broadcast();
  final List<int> _buffer = [];
  bool _closed = false;
  int _totalBytes = 0;

  void addChunk(List<int> bytes) {
    if (_closed) return;
    _totalBytes += bytes.length;
    _buffer.addAll(bytes);
    _broadcast.add(bytes);
  }

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

    final bufferedEnd = _buffer.length;
    final dataEnd = end > bufferedEnd ? bufferedEnd : end;
    final initialData = start < dataEnd
        ? Uint8List.fromList(_buffer.sublist(start, dataEnd))
        : Uint8List(0);

    final outputController = StreamController<List<int>>();

    if (initialData.isNotEmpty) {
      outputController.add(initialData);
    }

    if (_closed) {
      await outputController.close();
    } else {
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

/// 已保存的音频文件数据模型
class _SavedAudioFile {
  final String path;
  final String fileName;
  final int size;
  final DateTime savedAt;

  _SavedAudioFile({
    required this.path,
    required this.fileName,
    required this.size,
    required this.savedAt,
  });
}

/// API 测试页面中的语音合成 Tab
class ApiSpeechTabPage extends StatefulWidget {
  const ApiSpeechTabPage();

  @override
  State<ApiSpeechTabPage> createState() => _ApiSpeechTabPageState();
}

class _ApiSpeechTabPageState extends State<ApiSpeechTabPage> {
  static const String _kMinimaxiApiKey = 'minimaxi_api_key';

  final _apiKeyController = TextEditingController();
  final _textController = TextEditingController();
  final _customModelController = TextEditingController();

  String? _selectedVoiceId;
  String? _selectedVoiceName;
  String? _statusMessage;
  bool _isPlaying = false;
  bool _showAdvanced = false;
  bool _useStreaming = true;

  final List<int> _audioChunks = [];
  final List<_SavedAudioFile> _savedFiles = [];

  WebSocket? _ws;
  bool _isSynthesizing = false;
  int _chunkCount = 0;
  _WebSocketAudioSource? _streamSource;

  final AudioPlayer _player = AudioPlayer();

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
    _loadSavedApiKey();
  }

  Future<void> _loadSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kMinimaxiApiKey);
    if (saved != null && saved.isNotEmpty) {
      _apiKeyController.text = saved;
    }
  }

  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _apiKeyController.text.trim();
    if (key.isNotEmpty) {
      await prefs.setString(_kMinimaxiApiKey, key);
    } else {
      await prefs.remove(_kMinimaxiApiKey);
    }
  }

  Future<void> _clearApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空 API Key'),
        content: const Text('确定要清除已保存的 API Key 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kMinimaxiApiKey);
      _apiKeyController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API Key 已清除')),
        );
      }
    }
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
    await _saveApiKey();
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

  Future<void> _closeExistingConnection() async {
    _streamSource?.markComplete();
    _streamSource = null;
    await _ws?.close();
    _ws = null;
    _isSynthesizing = false;
    _chunkCount = 0;
  }

  Future<void> _synthesizeWebSocket(String model, String text) async {
    if (_isSynthesizing) {
      await _closeExistingConnection();
    }

    try {
      _isSynthesizing = true;
      _chunkCount = 0;
      _streamSource = _WebSocketAudioSource();

      _ws = await WebSocket.connect(
        'wss://api.minimaxi.com/ws/v1/t2a_v2',
        headers: {'Authorization': 'Bearer ${_apiKeyController.text}'},
      );

      setState(() => _statusMessage = '正在连接...');

      final iterator = StreamIterator(_ws!);

      if (!await iterator.moveNext()) {
        _isSynthesizing = false;
        setState(() => _statusMessage = '连接被关闭');
        return;
      }
      final welcome =
          json.decode(iterator.current as String) as Map<String, dynamic>;
      if (welcome['event'] != 'connected_success') {
        await _ws!.close();
        _isSynthesizing = false;
        setState(() => _statusMessage = '连接失败: ${iterator.current}');
        return;
      }

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
      _ws!.add(
        json.encode({
          'event': 'task_start',
          'model': model,
          'language_boost': _englishNormalization ? 'English' : 'Chinese',
          'voice_setting': voiceSetting,
          'audio_setting': audioSetting,
        }),
      );

      if (!await iterator.moveNext()) {
        _isSynthesizing = false;
        setState(() => _statusMessage = '连接被关闭');
        return;
      }
      final startResp =
          json.decode(iterator.current as String) as Map<String, dynamic>;
      if (startResp['event'] != 'task_started') {
        await _ws!.close();
        _isSynthesizing = false;
        setState(() => _statusMessage = '任务启动失败: ${iterator.current}');
        return;
      }

      _ws!.add(json.encode({'event': 'task_continue', 'text': text}));
      _ws!.add(json.encode({'event': 'task_finish'}));

      setState(() => _statusMessage = '流式合成中...');
      _startStreamPlayback();

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
              setState(
                () => _statusMessage =
                    '合成失败: ${message['base_resp']?['status_msg'] ?? '未知错误'}',
              );
              return;
            }
          } catch (e) {
            // 忽略解析错误
          }
        }

        if (audioBytes != null) {
          _chunkCount++;
          _audioChunks.addAll(audioBytes);
          _streamSource?.addChunk(audioBytes);
          setState(() {
            _statusMessage =
                '流式接收中... 已接收 $_chunkCount 个片段 (${_streamSource!.totalBytes ~/ 1024}KB)';
          });
        }
      }

      _isSynthesizing = false;
      setState(() {
        _statusMessage =
            '流式合成完成，共 $_chunkCount 个片段 (${_streamSource!.totalBytes ~/ 1024}KB)';
      });
    } catch (e) {
      _isSynthesizing = false;
      _streamSource?.markComplete();
      setState(() => _statusMessage = '流式合成异常: $e');
    }
  }

  void _startStreamPlayback() {
    setState(() {
      _isPlaying = true;
      _statusMessage = '正在播放流式音频...';
    });

    _player
        .setAudioSource(_streamSource!)
        .then((_) {
          _player.play();
        })
        .catchError((e) {
          if (mounted) {
            setState(() {
              _statusMessage = '播放失败: $e';
              _isPlaying = false;
            });
          }
        });
  }

  Future<void> _synthesizeHttp(String model, String text) async {
    try {
      final uri = Uri.parse('https://api.minimaxi.com/v1/t2a_v2');
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(uri);

      request.headers.set('Authorization', 'Bearer ${_apiKeyController.text}');
      request.headers.set('Content-Type', 'application/json; charset=utf-8');

      final requestBody = <String, dynamic>{
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
      };

      final bodyBytes = utf8.encode(json.encode(requestBody));
      request.add(bodyBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final responseData = json.decode(responseBody);
        if (responseData['data'] != null &&
            responseData['data']['audio'] != null) {
          final audioHex = responseData['data']['audio'] as String;
          final audioBytes = _hexToBytes(audioHex);
          _audioChunks.addAll(audioBytes);
          setState(
            () => _statusMessage = '合成完成，音频大小: ${audioBytes.length} bytes',
          );
          await _playAudio();
          await _saveAudioToFile(audioBytes);
        } else {
          setState(() => _statusMessage = '响应格式错误: $responseData');
        }
      } else {
        setState(
          () => _statusMessage = '请求失败: ${response.statusCode} - $responseBody',
        );
      }
    } catch (e) {
      setState(() => _statusMessage = '请求异常: $e');
    }
  }

  Future<void> _saveAudioToFile(List<int> audioBytes) async {
    try {
      final directory = await _getSaveDirectory();
      if (directory == null) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = _format == 'wav'
          ? 'wav'
          : (_format == 'pcm' ? 'pcm' : 'mp3');
      final filePath = '${directory.path}/tts_$timestamp.$extension';
      final file = File(filePath);
      await file.writeAsBytes(audioBytes);

      final savedFile = _SavedAudioFile(
        path: filePath,
        fileName: 'tts_$timestamp.$extension',
        size: audioBytes.length,
        savedAt: DateTime.now(),
      );
      _savedFiles.insert(0, savedFile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存: $filePath'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: '好的', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      debugPrint('保存音频文件失败: $e');
    }
  }

  Future<Directory?> _getSaveDirectory() async {
    try {
      if (Platform.isAndroid) {
        final pathProvider = await _getPathProvider();
        if (pathProvider != null) {
          return Directory(pathProvider);
        }
      }
      return await getTemporaryDirectory();
    } catch (e) {
      return await getTemporaryDirectory();
    }
  }

  Future<String?> _getPathProvider() async {
    try {
      final dir = await getTemporaryDirectory();
      return dir.path;
    } catch (e) {
      return null;
    }
  }

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

  Future<void> _manualSaveAudio() async {
    if (_audioChunks.isEmpty) {
      setState(() => _statusMessage = '没有可保存的音频');
      return;
    }
    await _saveAudioToFile(_audioChunks);
  }

  Future<void> _deleteSavedFile(int index) async {
    if (index < 0 || index >= _savedFiles.length) return;
    final file = _savedFiles[index];
    try {
      final f = File(file.path);
      if (await f.exists()) {
        await f.delete();
      }
      setState(() {
        _savedFiles.removeAt(index);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除: ${file.fileName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('删除文件失败: $e');
      setState(() {
        _savedFiles.removeAt(index);
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Future<void> _playSavedFile(_SavedAudioFile file) async {
    try {
      final f = File(file.path);
      if (!await f.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('文件不存在或已被删除')));
        }
        return;
      }
      final bytes = await f.readAsBytes();
      final audioData = Uint8List.fromList(bytes);
      final source = AudioSource.uri(
        Uri.dataFromBytes(audioData, mimeType: 'audio/mpeg'),
      );
      await _player.stop();
      await _player.setAudioSource(source);
      await _player.play();
      setState(() {
        _isPlaying = true;
        _statusMessage = '正在播放: ${file.fileName}';
      });
    } catch (e) {
      debugPrint('播放保存的文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播放失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Text(
                  'MiniMax 语音合成',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API Key',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      hintText: '输入您的 API Key',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _apiKeyController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _clearApiKey,
                              tooltip: '清除已保存的 Key',
                            )
                          : null,
                    ),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
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
                  Row(
                    children: [
                      const Text(
                        '选择模型',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showAdvanced = !_showAdvanced),
                        icon: Icon(
                          _showAdvanced
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
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
                    items: _models
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.$1,
                            child: Text(m.$2),
                          ),
                        )
                        .toList(),
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

          if (_showAdvanced) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '语音设置',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                        SizedBox(
                          width: 50,
                          child: Text(_speed.toStringAsFixed(1)),
                        ),
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
                        SizedBox(
                          width: 50,
                          child: Text(_vol.toStringAsFixed(1)),
                        ),
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
                        SizedBox(
                          width: 50,
                          child: Text(_pitch.toStringAsFixed(0)),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('英文正则化'),
                      value: _englishNormalization,
                      onChanged: (v) =>
                          setState(() => _englishNormalization = v),
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
                    const Text(
                      '音频设置',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('采样率')),
                        Expanded(
                          child: SegmentedButton<int>(
                            segments: _sampleRates
                                .map(
                                  (r) => ButtonSegment(
                                    value: r,
                                    label: Text('${r ~/ 1000}k'),
                                  ),
                                )
                                .toList(),
                            selected: {_sampleRate},
                            onSelectionChanged: (s) =>
                                setState(() => _sampleRate = s.first),
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
                            segments: _bitrates
                                .map(
                                  (r) => ButtonSegment(
                                    value: r,
                                    label: Text('${r ~/ 1000}k'),
                                  ),
                                )
                                .toList(),
                            selected: {_bitrate},
                            onSelectionChanged: (s) =>
                                setState(() => _bitrate = s.first),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('格式')),
                        SegmentedButton<String>(
                          segments: _formats
                              .map(
                                (f) => ButtonSegment(
                                  value: f,
                                  label: Text(f.toUpperCase()),
                                ),
                              )
                              .toList(),
                          selected: {_format},
                          onSelectionChanged: (s) =>
                              setState(() => _format = s.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('声道')),
                        SegmentedButton<int>(
                          segments: _channels
                              .map(
                                (c) => ButtonSegment(
                                  value: c,
                                  label: Text(c == 1 ? '单声道' : '立体声'),
                                ),
                              )
                              .toList(),
                          selected: {_channel},
                          onSelectionChanged: (s) =>
                              setState(() => _channel = s.first),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择音色',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '中文音色',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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
                  const Text(
                    '英文音色',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Text(
                        '已选择: $_selectedVoiceName',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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
                  const Text(
                    '合成文本',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                  const Text(
                    '快速测试文本',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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

          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusMessage!.contains('失败') ||
                        _statusMessage!.contains('错误')
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
                      _statusMessage!.contains('失败') ||
                              _statusMessage!.contains('错误')
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
                        color: _statusMessage!.contains('失败') ||
                                _statusMessage!.contains('错误')
                            ? Colors.red[700]
                            : Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          Card(
            child: SwitchListTile(
              title: const Text('流式输出'),
              subtitle: Text(
                _useStreaming
                    ? 'WebSocket 边合成边播放'
                    : 'HTTP 等待合成完成后再播放',
              ),
              value: _useStreaming,
              onChanged: (v) => setState(() => _useStreaming = v),
              secondary: Icon(
                _useStreaming ? Icons.stream : Icons.cloud_download,
                color: _useStreaming ? Colors.green : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 16),

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
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _audioChunks.isEmpty ? null : _manualSaveAudio,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('保存'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_savedFiles.isNotEmpty) ...[
            const Text(
              '已保存音频',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _savedFiles.length,
                itemBuilder: (context, index) {
                  final file = _savedFiles[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.audio_file),
                      title: Text(
                        file.fileName,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${_formatFileSize(file.size)} • ${_formatTime(file.savedAt)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteSavedFile(index),
                        tooltip: '删除',
                      ),
                      onTap: () => _playSavedFile(file),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
