// lib/lab/demos/remotetype/rt_page.dart
//
// RemoteType demo 主页面：两态。
//   配对页 —— 服务器地址 + 配对 key + 目标 PC（留空自动选唯一在线 PC）
//   输入页 —— 全文同步输入框 + ASR 麦克风 + 端到端指示
//
// 同步触发规则（见 plan §5）：
//   - IME composing 中挂起（拼音中间态不上传），合成结束补发
//   - ASR partial 直发（diff 自愈，实时上屏是特性）
//   - 250ms 防抖

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'rt_constants.dart';
import 'rt_session.dart';

class RemoteTypePage extends StatefulWidget {
  const RemoteTypePage({super.key});

  @override
  State<RemoteTypePage> createState() => _RemoteTypePageState();
}

class _RemoteTypePageState extends State<RemoteTypePage> {
  RtSession? _session;
  bool _connecting = false;
  String? _error;

  // 配对页输入
  final _serverController = TextEditingController();
  final _keyController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _tokenController = TextEditingController();

  // 输入页状态
  final _textController = TextEditingController();
  Timer? _debounce;
  bool _e2eOk = false;
  bool _connected = false;
  StreamSubscription<RtEvent>? _eventSub;

  // ASR
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _listening = false;
  bool _sttAvailable = false;
  String _asrBase = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _eventSub?.cancel();
    _textController.dispose();
    _serverController.dispose();
    _keyController.dispose();
    _clientIdController.dispose();
    _tokenController.dispose();
    if (_listening) _stt.stop();
    _session?.dispose();
    super.dispose();
  }

  // ================= 连接 =================

  Future<void> _connect() async {
    final server = _serverController.text.trim();
    final key = _keyController.text.trim();
    var clientId = _clientIdController.text.trim();

    if (server.isEmpty || key.isEmpty) {
      setState(() => _error = '请填写服务器地址与配对 key');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    // 目标 PC 留空时：拉在线列表，唯一在线则自动选中
    if (clientId.isEmpty) {
      try {
        final online = await RtSession.listClients(server);
        if (online.isEmpty) {
          setState(() {
            _connecting = false;
            _error = '服务器上没有在线的 PC——请先在电脑上运行 remotetype serve';
          });
          return;
        }
        if (online.length > 1) {
          setState(() {
            _connecting = false;
            _error = '有多台 PC 在线（${online.join('、 ')}），请填写目标 clientId';
          });
          return;
        }
        clientId = online.single;
      } on RtSessionException catch (e) {
        setState(() {
          _connecting = false;
          _error = e.message;
        });
        return;
      } catch (e) {
        setState(() {
          _connecting = false;
          _error = '无法访问服务器（$e）';
        });
        return;
      }
    }

    final session = RtSession(
      serverUrl: server,
      key: key,
      targetClientId: clientId,
      token: _tokenController.text.trim().isEmpty ? null : _tokenController.text.trim(),
    );
    try {
      await session.connect();
    } on RtSessionException catch (e) {
      await session.dispose();
      setState(() {
        _connecting = false;
        _error = e.message;
      });
      return;
    } catch (e) {
      await session.dispose();
      setState(() {
        _connecting = false;
        _error = '连接失败：$e';
      });
      return;
    }

    _eventSub = session.events.listen(_onEvent);
    setState(() {
      _session = session;
      _connecting = false;
      _connected = true;
    });
  }

  void _onEvent(RtEvent e) {
    if (!mounted) return;
    switch (e.kind) {
      case RtEventKind.e2eConfirmed:
        setState(() => _e2eOk = true);
      case RtEventKind.connected:
        setState(() => _connected = true);
      case RtEventKind.disconnected:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接断开（${e.detail ?? ''}）')),
        );
      case RtEventKind.deliveryFailed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.detail ?? '投递失败')),
        );
      case RtEventKind.error:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.detail ?? '未知错误')));
    }
  }

  // ================= 同步 =================

  void _onTextChanged(String _) {
    final value = _textController.value;
    // IME 合成中挂起（合成结束的变更会再次触发本回调）
    if (value.composing != TextRange.empty) {
      return;
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    final session = _session;
    if (session == null) return;
    _debounce?.cancel();
    _debounce = Timer(kRtSyncDebounce, () {
      final text = _textController.text;
      session.syncText(text).catchError((Object e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失败：$e')));
        }
      });
    });
  }

  // ================= ASR =================

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      _asrBase = _textController.text;
      return;
    }

    if (!_sttAvailable) {
      _sttAvailable = await _stt.initialize(
        onError: (e) => debugPrint('stt error: ${e.errorMsg}'),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _listening) {
              setState(() {
                _listening = false;
                _asrBase = _textController.text;
              });
            }
          }
        },
      );
      if (!_sttAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('语音识别不可用（权限或引擎缺失）')),
          );
        }
        return;
      }
    }

    _asrBase = _textController.text;
    await _stt.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        final text = _asrBase + (result.finalResult ? '' : words);
        _textController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        if (result.finalResult) _asrBase = text;
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        localeId: 'zh_CN',
      ),
    );
    setState(() => _listening = true);
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程输入（联机）'),
        actions: [
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: '断开并返回配对',
              onPressed: () {
                _eventSub?.cancel();
                _session?.dispose();
                _session = null;
                _debounce?.cancel();
                if (_listening) _stt.stop();
                setState(() {
                  _connected = false;
                  _e2eOk = false;
                  _listening = false;
                });
              },
            ),
        ],
      ),
      body: _session == null ? _buildPairing() : _buildInput(context),
    );
  }

  Widget _buildPairing() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.keyboard_alt_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              '把手机变成电脑的输入设备',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '如 http://192.168.1.10:8899',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: '配对 key',
                hintText: '电脑端 remotetype serve --align 打印的 key',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientIdController,
              decoration: const InputDecoration(
                labelText: '目标 PC（可选）',
                hintText: '留空 = 自动选择唯一在线 PC',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: '访问 token（可选）',
                hintText: '服务器设了 RT_TOKEN 时填写',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: Text(_connecting ? '连接中…' : '连接电脑'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            const Text(
              '端到端加密：文本在手机加密、电脑解密，中转服务器只经手密文。\n'
              'key 即凭据，请勿外传。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Icon(
                _e2eOk ? Icons.lock : Icons.lock_open,
                size: 16,
                color: _e2eOk ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                _e2eOk
                    ? '端到端已建立'
                    : (_connected ? '已连接，等待电脑确认（发一条消息即确认）' : '连接中…'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _textController,
              onChanged: _onTextChanged,
              maxLines: null,
              expands: true,
              maxLength: kRtMaxTextLength,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '在这里打字或说话，内容（含删除）实时对齐到电脑焦点输入框…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _toggleListening,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(_listening ? '停止' : '语音'),
                style: FilledButton.styleFrom(
                  backgroundColor: _listening ? Colors.red.shade100 : null,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  _asrBase = '';
                  _textController.clear();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('清空'),
              ),
              const Spacer(),
              if (_listening)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.graphic_eq, color: Colors.red),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
