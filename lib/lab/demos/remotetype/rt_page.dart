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

  // 配对页状态：服务器地址内置（kRemoteTypeServerUrl），流程 = 先选 PC → 再填 key
  final _keyController = TextEditingController();
  final _tokenController = TextEditingController();
  List<String> _clients = const [];
  bool _clientsLoading = false;
  String? _selectedClient;
  Timer? _pollTimer;

  // 输入页状态
  final _textController = TextEditingController();
  Timer? _debounce;
  bool _e2eOk = false;
  bool _connected = false;
  StreamSubscription<RtEvent>? _eventSub;
  // 配对未确认提示：key 不一致时 PC 端会静默丢弃全部信封，
  // 不提示的话用户只看到「打了字没同步」，无从自查
  Timer? _e2eHintTimer;
  bool _e2eHintShown = false;
  // 合成区缓滞上传：输入法语音识别常把已识别汉字长期留在 composing 区
  Timer? _composingTimer;
  // 控制器事件状态：onChanged 只在文本变化时触发，「结束合成」（composing
  // 清空但文本不变）那帧只有 controller 监听能捕获——语音文字卡同步的根因
  bool _wasComposing = false;
  String _lastEventText = '';
  // 联调可观测性：本次会话已发出的同步包数（对照 PC 端 envelopesOk，
  // 立刻区分「手机没发」还是「电脑没收」）
  int _syncSent = 0;
  // 焦点漂移：PC 端告诉我们焦点离开了目标输入框（注入已暂停）
  bool _focusPaused = false;

  // ASR
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _listening = false;
  bool _sttAvailable = false;
  String _asrBase = '';
  // 识别器楔死自救：插件跨 listen 复用 SpeechRecognizer 实例且错误路径不 destroy，
  // 国产 ROM 厂商引擎（与输入法语音同源）会把出错实例楔在 busy 态——之后永久
  // error_busy，直到 app 重启。翻转 onDevice 触发插件 createRecognizer 的
  // 销毁重建分支，拿到全新实例（onDevice 可用时还顺带切到本地离线引擎）。
  bool _sttRebuildTick = false;
  bool _busyRetryPending = false; // busy 自动重试进行中，防递归

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onControllerChanged);
    _refreshClients();
    // 配对页可见期间轮询在线列表（连上后页面切换，轮询空转开销可忽略）
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_session == null) _refreshClients();
    });
  }

  Future<void> _refreshClients() async {
    if (_clientsLoading) return;
    _clientsLoading = true;
    try {
      final list = await RtSession.listClients(kRemoteTypeServerUrl);
      if (!mounted) return;
      setState(() {
        _clients = list;
        // 单台在线自动预选（仍可改选）；已选的掉线则清空
        if (_selectedClient == null && list.length == 1) _selectedClient = list.single;
        if (_selectedClient != null && !list.contains(_selectedClient)) _selectedClient = null;
      });
    } catch (_) {
      // 服务器暂不可达：保留旧列表，空态文案由列表为空时展示
    } finally {
      _clientsLoading = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _debounce?.cancel();
    _composingTimer?.cancel();
    _e2eHintTimer?.cancel();
    _eventSub?.cancel();
    _textController.removeListener(_onControllerChanged);
    _textController.dispose();
    _keyController.dispose();
    _tokenController.dispose();
    if (_listening) _stt.stop();
    _session?.dispose();
    super.dispose();
  }

  // ================= 连接 =================

  Future<void> _connect() async {
    final key = _keyController.text.trim();
    final token = _tokenController.text.trim();

    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在列表中选择要连接的 PC')),
      );
      return;
    }
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入配对 key')),
      );
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    final session = RtSession(
      serverUrl: kRemoteTypeServerUrl,
      key: key,
      targetClientId: _selectedClient!,
      token: token.isEmpty ? null : token,
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
      _e2eOk = false;
      _e2eHintShown = false;
      _focusPaused = false;
    });
  }

  void _onEvent(RtEvent e) {
    if (!mounted) return;
    switch (e.kind) {
      case RtEventKind.e2eConfirmed:
        _e2eHintTimer?.cancel();
        setState(() => _e2eOk = true);
      case RtEventKind.focusPaused:
        setState(() => _focusPaused = true);
      case RtEventKind.focusResumed:
        setState(() => _focusPaused = false);
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

  /// 控制器级监听（不用 onChanged：它只在文本变化时触发，收尾帧捕获不到）。
  ///
  /// 输入法语音的完整事件序列：
  ///   ① 语音逐字上屏：文本变 + composing 挂着 → 挂起（拼音中间态不上传）
  ///   ② 结束合成：composing 清空但【文本不变】→ 只有这里能捕获 → 补发
  ///   ③ 部分输入法从不结束合成 → 静默 1.5s 且合成区已是汉字 → 直接上传
  void _onControllerChanged() {
    final v = _textController.value;
    final composing = v.composing != TextRange.empty;
    final textChanged = v.text != _lastEventText;

    if (composing) {
      _wasComposing = true;
      if (!textChanged) return; // 纯光标/选区移动
      _lastEventText = v.text;
      _composingTimer?.cancel();
      _composingTimer = Timer(const Duration(milliseconds: 1500), () {
        final vv = _textController.value;
        if (!mounted || vv.composing == TextRange.empty) return;
        if (_hasCjk(vv.composing.textInside(vv.text))) {
          _lastEventText = vv.text;
          _scheduleSync();
        }
      });
      return;
    }

    _composingTimer?.cancel();
    final wasComposing = _wasComposing;
    _wasComposing = false;
    if (textChanged || wasComposing) {
      _lastEventText = v.text;
      _scheduleSync();
    }
  }

  /// 是否含 CJK 统表汉字（语音识别中间结果；拼音拼写中间态只含 ASCII）
  static bool _hasCjk(String s) {
    for (final r in s.runes) {
      if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) return true;
    }
    return false;
  }

  void _scheduleSync() {
    final session = _session;
    if (session == null) return;
    // 配对未确认：延迟 2.5s 仍无 ACK 则提示一次（正常 ACK 往返 < 1s）
    if (!_e2eOk) {
      _e2eHintTimer?.cancel();
      _e2eHintTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted && !_e2eOk && !_e2eHintShown) {
          _e2eHintShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('电脑端未确认配对：请核对两端配对 key 是否完全一致'
                  '（电脑端重启 serve 会生成新 key）'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      });
    } else {
      _e2eHintTimer?.cancel();
    }
    _debounce?.cancel();
    _debounce = Timer(kRtSyncDebounce, () {
      final text = _textController.text;
      session.syncText(text).then((_) {
        if (mounted) setState(() => _syncSent += 1);
      }).catchError((Object e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失败：$e')));
        }
      });
    });
  }

  // ================= ASR =================

  /// 复位录音状态：错误路径下 onStatus 不一定回调 done/notListening，
  /// 不主动复位按钮会卡在「停止」态且识别器不释放。
  void _resetListening() {
    if (_listening) {
      unawaited(_stt.stop());
    }
    if (mounted) {
      setState(() => _listening = false);
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      _asrBase = _textController.text;
      return;
    }

    if (!_sttAvailable) {
      _sttAvailable = await _stt.initialize(
        onError: (e) {
          debugPrint('stt error: ${e.errorMsg}');
          if (!mounted) return;
          // 引擎层错误上浮；no_match / speech_timeout 是说话停顿的非致命反馈，不打扰
          const benign = {'error_no_match', 'error_speech_timeout'};
          if (benign.contains(e.errorMsg)) return;
          // 非 benign 错误一律强制重建识别器（见 _sttRebuildTick 注释），
          // 否则厂商引擎的楔死实例会让后续每次 listen 都 busy
          _sttRebuildTick = !_sttRebuildTick;
          _resetListening();
          // busy：实例楔死的典型表现，销毁重建后自动重试一次
          if (e.errorMsg == 'error_busy') {
            if (_busyRetryPending) {
              _busyRetryPending = false;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('语音识别引擎繁忙：重试仍失败，请重启输入法（或重启手机）后再试'),
                ),
              );
              return;
            }
            _busyRetryPending = true;
            Timer(const Duration(milliseconds: 800), () {
              if (mounted && !_listening) _toggleListening();
            });
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('语音识别错误：${e.errorMsg}')),
          );
        },
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
    try {
      await _stt.listen(
        // speech_to_text 契约：partial 与 final 的 recognizedWords 都是
        // 「本段完整识别文本」（Android SpeechToTextPlugin.updateResults
        // 只取 RESULTS_RECOGNITION[0]），final 到达时把该段并入 base。
        // 不能在 final 时丢弃 words——那会把刚说完的话整段清空。
        onResult: (result) {
          final text = _asrBase + result.recognizedWords;
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
          onDevice: _sttRebuildTick,
        ),
      );
    } catch (e) {
      // listen 抛异常（如引擎服务缺失）不能无声吞掉，否则按钮像坏了
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音启动失败：$e')),
        );
      }
      return;
    }
    _busyRetryPending = false;
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
                _composingTimer?.cancel();
                _e2eHintTimer?.cancel();
                if (_listening) _stt.stop();
                setState(() {
                  _connected = false;
                  _e2eOk = false;
                  _listening = false;
                  _e2eHintShown = false;
                  _focusPaused = false;
                });
              },
            ),
        ],
      ),
      body: _session == null ? _buildPairing() : _buildInput(context),
    );
  }

  Widget _buildPairing() {
    final cs = Theme.of(context).colorScheme;
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
            // ① 选 PC（列表自动轮询，单台在线自动预选）
            Row(
              children: [
                Text('① 选择电脑', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _refreshClients,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ],
            ),
            if (_clients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _clientsLoading ? '正在获取在线 PC…' : '暂无 PC 上线——请先在电脑上运行 remotetype serve --align',
                  style: TextStyle(color: cs.outline),
                ),
              )
            else
              ..._clients.map((cid) {
                final selected = cid == _selectedClient;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedClient = cid),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 18,
                            color: selected ? cs.primary : cs.outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(cid, style: const TextStyle(fontFamily: 'monospace')),
                          ),
                          Text('在线', style: TextStyle(fontSize: 11, color: cs.outline)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            // ② 填 key
            Text('② 配对 key', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                hintText: '电脑端 remotetype serve --align 打印的 key',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
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
              child: Text(_connecting ? '连接中…' : '实时同步连接'),
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
        if (_focusPaused)
          Container(
            width: double.infinity,
            color: Colors.orange.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.pause_circle, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '电脑端焦点已离开目标输入框，注入暂停\n点回原输入框后自动恢复',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
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
              Expanded(
                child: Text(
                  '${_e2eOk
                      ? '端到端已建立'
                      : (_connected ? '已连接，等待电脑确认（发一条消息即确认）' : '连接中…')}'
                  '　已发 $_syncSent 包 · $kRtBuildTag',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _textController,
              onTapOutside: (_) {
                // 点输入框外通常触发 IME 收起/合成结束；合成区仍挂着时兜底强制同步，
                // 覆盖「合成永不结束也不再有文本变更」的输入法
                if (_textController.value.composing != TextRange.empty) {
                  _scheduleSync();
                }
              },
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
