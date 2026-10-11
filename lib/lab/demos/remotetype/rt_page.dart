// lib/lab/demos/remotetype/rt_page.dart
//
// RemoteType demo 主页面：两态。
//   配对页 —— 优先「统一登录 → 我名下的电脑 → 点一下即连」；
//             服务端没开启统一登录时才退回「选 PC + 填配对 key」
//   输入页 —— 全文同步输入框 + ASR 麦克风 + 端到端指示
//
// 同步触发规则（见 plan §5）：
//   - IME composing 中挂起（拼音中间态不上传），合成结束补发
//   - ASR partial 直发（diff 自愈，实时上屏是特性）
//   - 250ms 防抖

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../api/remotetype/remotetype.dart';
import '../../../services/remotetype/remotetype_providers.dart';
import '../../../services/remotetype/remotetype_service.dart';
import 'rt_constants.dart';
import 'rt_session.dart';

class RemoteTypePage extends ConsumerStatefulWidget {
  const RemoteTypePage({super.key});

  @override
  ConsumerState<RemoteTypePage> createState() => _RemoteTypePageState();
}

class _RemoteTypePageState extends ConsumerState<RemoteTypePage> {
  RtSession? _session;
  bool _connecting = false;
  String? _error;

  // 配对页状态：服务器地址内置（kRemoteTypeServerUrl）
  //
  // 两条路径并存，因为线上同时存在两种部署：
  //   统一登录（首选）—— 列出**我名下**的电脑，密钥由服务端按属主下发，零输入；
  //   手工配对（兜底）—— 服务端没开统一登录时，仍按老办法填 key。
  // _unified == null 表示还没探完，UI 不预设任何一条路径的界面。
  bool? _unified;
  RemoteTypeReadiness? _readiness;
  final _keyController = TextEditingController();
  List<String> _clients = const [];
  List<RtComputer> _computers = const [];
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
  // 回车注入方式：'enter'=发送（电脑端敲普通 Enter）/ 'shift_enter'=换行
  // （电脑端敲 Shift+Enter，微信等「Enter=发送」的框里只换行不发送）。
  // 随每条快照下发，可即时切换；页面级内存态（本页其他配置同样不持久化）
  String _enterMode = 'enter';

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
    _bootstrap();
    // 配对页可见期间轮询在线列表（连上后页面切换，轮询空转开销可忽略）
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_session == null) _refreshClients();
    });
  }

  /// 先探一次"这台服务器走不走统一登录"，再决定配对页长什么样。
  ///
  /// 探测结果必须落到界面上而不是只在日志里：服务端开着开关但连不上认证中心时，
  /// 不探的话用户看到的是"点了没反应"，探了才能一句话说清是谁的问题。
  Future<void> _bootstrap() async {
    final ready = await ref.read(remoteTypeServiceProvider).readiness();
    if (!mounted) return;
    setState(() {
      _unified = ready.available;
      _readiness = ready;
    });
    _refreshClients();
  }

  Future<void> _refreshClients() async {
    if (_clientsLoading) return;
    _clientsLoading = true;
    final unified = _unified == true;
    try {
      if (unified) {
        final list =
            await ref.read(remoteTypeServiceProvider).myComputers();
        if (!mounted) return;
        setState(() {
          _computers = list;
          // 单台在线自动预选（仍可改选）；已选的掉线则清空
          final online = list.where((c) => c.online).toList();
          if (_selectedClient == null && online.length == 1) {
            _selectedClient = online.single.clientId;
          }
          if (_selectedClient != null &&
              !list.any((c) => c.clientId == _selectedClient && c.online)) {
            _selectedClient = null;
          }
        });
      } else {
        final list = await RtSession.listClients(kRemoteTypeServerUrl);
        if (!mounted) return;
        setState(() {
          _clients = list;
          if (_selectedClient == null && list.length == 1) {
            _selectedClient = list.single;
          }
          if (_selectedClient != null && !list.contains(_selectedClient)) {
            _selectedClient = null;
          }
        });
      }
    } on RemoteTypeException catch (e) {
      if (!mounted) return;
      // 凭据失效不静默：清掉后重新探一次，让界面回到"要么能列、要么说清为什么不能"
      if (e.kind == RemoteTypeErrorKind.unauthorized) {
        await ref.read(remoteTypeServiceProvider).signOut();
        setState(() => _error = e.message);
        _bootstrap();
      } else {
        setState(() => _error = e.message);
      }
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
    if (_listening) _stt.stop();
    _session?.dispose();
    super.dispose();
  }

  // ================= 连接 =================

  Future<void> _connect() async {
    final unified = _unified == true;
    // 不是 final：统一登录路径下密钥由服务端下发，要在这里覆盖掉输入框的内容
    var key = _keyController.text.trim();

    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在列表中选择要连接的电脑')),
      );
      return;
    }
    // 统一登录路径下 key 来自服务端；走到这里还拿不到就是列表过期了，
    // 提示刷新比让用户去填一个他不知道的 key 有用得多。
    if (!unified && key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入配对 key')),
      );
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    String? deviceToken;
    if (unified) {
      final matched = _computers.where((c) => c.clientId == _selectedClient);
      if (matched.isEmpty || matched.first.sessionKey.isEmpty) {
        setState(() {
          _connecting = false;
          _error = '设备列表已过期，请下拉刷新后重试';
        });
        return;
      }
      key = matched.first.sessionKey;
      final grant =
          await ref.read(remoteTypeServiceProvider).ensureGrant();
      deviceToken = grant?.token;
    }

    final session = RtSession(
      serverUrl: kRemoteTypeServerUrl,
      key: key,
      targetClientId: _selectedClient!,
      deviceToken: deviceToken,
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
    });
  }

  void _onEvent(RtEvent e) {
    if (!mounted) return;
    switch (e.kind) {
      case RtEventKind.e2eConfirmed:
        _e2eHintTimer?.cancel();
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
      // 发送模式 + 句尾 Enter =「发送」：PC 端注入 Enter 后目标框清空、
      // mirror 归零（rt-align commitApplied），手机端同步清空开始新一条，
      // 两侧对齐到空。空卡回车（只有换行）不发包，直接开新卡。
      final flushAfterSend = _enterMode == 'enter' && text.endsWith('\n');
      if (flushAfterSend && text.trim().isEmpty) {
        _asrBase = '';
        _textController.clear();
        return;
      }
      session.syncText(text, enterMode: _enterMode).then((sent) {
        if (!mounted) return;
        if (sent) {
          setState(() => _syncSent += 1);
          if (flushAfterSend) {
            _asrBase = '';
            _textController.clear();
          }
        }
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

  // ================= 快捷键面板 =================

  /// 弹出快捷键网格。onFire 回调在每次点击时读取当前 `_session`：
  /// 断开重连后 sheet 里拿到的是新会话，不用重建面板。
  void _showShortcutSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ShortcutPanel(
        e2eOk: () => _e2eOk,
        onFire: (keys) async {
          final session = _session;
          if (session == null) return '未连接电脑';
          if (!_e2eOk) return '等待端到端确认（先发一条消息）';
          final sent = await session.syncHotkey(keys);
          return sent ? null : '发送失败（连接已断开？）';
        },
      ),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 键盘不压缩页面：输入框固定高度，键盘直接覆盖底部（与网页控制台一致）。
      // 配对页自行用 viewInsets 兜底（见 _buildPairing）。
      resizeToAvoidBottomInset: false,
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
    // Scaffold 已关 resizeToAvoidBottomInset：这里用 viewInsets 把整块内容
    // 抬到键盘上方，SingleChildScrollView 保证极小屏仍可滚动
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
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
            if (_unified == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_unified!)
              // ── 统一登录：我名下的电脑，点一下即连 ──────────────────────
              // 没有 key 输入框，也没有 token 输入框。密钥由服务端按属主下发，
              // 用户不需要知道它的存在，也就没有"复制错一台"这种事。
              ...[
                Row(
                  children: [
                    Text('我的电脑', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _clientsLoading ? null : _refreshClients,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                    ),
                  ],
                ),
                if (_computers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _clientsLoading
                          ? '正在获取你的电脑…'
                          : '还没有登记在你名下的电脑。\n'
                              '在电脑上执行：npx nx-rt auth login --url ${kRemoteTypeServerUrl.replaceFirst('http', 'ws')}/ws\n'
                              '然后再执行 npx nx-rt 即可。',
                      style: TextStyle(color: cs.outline),
                    ),
                  )
                else
                  ..._computers.map(_buildComputerTile),
              ]
            else
              // ── 兜底：服务端没开统一登录，回到手工配对 key ───────────────
              ...[
                if (_readiness != null && _readiness!.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _readiness!.reason,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ),
                Row(
                  children: [
                    Text('① 选择电脑',
                        style: Theme.of(context).textTheme.titleSmall),
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
                      _clientsLoading
                          ? '正在获取在线 PC…'
                          : '暂无 PC 上线——请先在电脑上运行 remotetype serve --align',
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    selected ? cs.primary : cs.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 18,
                                color: selected ? cs.primary : cs.outline,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(cid,
                                    style:
                                        const TextStyle(fontFamily: 'monospace')),
                              ),
                              Text('在线',
                                  style: TextStyle(
                                      fontSize: 11, color: cs.outline)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text('② 配对 key',
                    style: Theme.of(context).textTheme.titleSmall),
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
              ],
            FilledButton(
              onPressed: _connecting ? null : _connect,
              child: Text(_connecting
                  ? '连接中…'
                  : (_unified == true ? '连接选中的电脑' : '实时同步连接')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            Text(
              _unified == true
                  ? '文本在手机加密、电脑解密；会话密钥由统一登录按账号下发，\n'
                      '同一账号下的手机与电脑自动配对，无需复制任何 key。\n'
                      '注意：密钥经服务端分发，服务方可读明文（详见 mn-rt README）。'
                  : '端到端加密：文本在手机加密、电脑解密，中转服务器只经手密文。\n'
                      'key 即凭据，请勿外传。',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// 一台我名下的电脑。在线才可点，且**点一下就直接连**——不再分"选中"和"连接"两步。
  Widget _buildComputerTile(RtComputer c) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // 离线也可选中（连着不存在的电脑没意义，但报错信息比按钮灰掉更有用）
        onTap: () {
          setState(() => _selectedClient = c.clientId);
          if (c.online) _connect();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: c.clientId == _selectedClient ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                c.online ? Icons.desktop_windows : Icons.desktop_access_disabled,
                size: 18,
                color: c.online ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.label),
                    Text(
                      c.clientId,
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
              ),
              Text(
                c.online ? '在线 · 点击连接' : '不在线',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    // 输入框固定高度（屏高的 40%，夹在 180-340 之间）：Scaffold 已关
    // resizeToAvoidBottomInset，键盘弹起时布局纹丝不动，键盘直接盖住底部。
    final double fieldHeight =
        (MediaQuery.sizeOf(context).height * 0.4).clamp(180.0, 340.0);
    return SafeArea(
      child: Column(
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
          // 回车注入开关独占一行：此前挤在语音/清空按钮行里，大字体或手势条
          // 遮挡时 Row 溢出裁剪，最右侧「换行」段点不到（切换失灵的根因）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                Text('回车注入', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'enter',
                      label: Text('发送', style: TextStyle(fontSize: 13)),
                      tooltip: '电脑端敲普通 Enter——多数输入框即「发送」',
                    ),
                    ButtonSegment(
                      value: 'shift_enter',
                      label: Text('换行', style: TextStyle(fontSize: 13)),
                      tooltip: '电脑端敲 Shift+Enter——微信等框里只换行不发送',
                    ),
                  ],
                  selected: {_enterMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() => _enterMode = selection.first);
                    // 模式随快照传输：立即补发一条，切换即刻生效
                    //（否则要等下一次文本变化才带上新模式）
                    _scheduleSync();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _enterMode == 'enter' ? '电脑端敲 Enter（= 发送）' : '电脑端敲 Shift+Enter（换行不发送）',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: fieldHeight,
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
          const Spacer(),
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
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showShortcutSheet,
                  icon: const Icon(Icons.keyboard_command_key),
                  label: const Text('快捷键'),
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
      ),
    );
  }
}

/// 快捷键网格（bottom sheet 内容）。
///
/// 预设来自 [kShortcutPresets]（两端协议约定：末位主键、其余修饰键）。
/// 每个按钮独立 in-flight 态：发送中转圈禁点，结果用 SnackBar 反馈——
/// PC 端对 hotkey 是「受理即 ACK」，点完就该假定已触发，不做重试。
class _ShortcutPanel extends StatefulWidget {
  const _ShortcutPanel({
    required this.e2eOk,
    required this.onFire,
  });

  /// 每次点击时实时读取（E2E 确认可能在面板打开期间才完成）。
  final bool Function() e2eOk;

  /// 返回 null = 成功；非 null = 给用户看的错误文案。
  final Future<String?> Function(List<String> keys) onFire;

  @override
  State<_ShortcutPanel> createState() => _ShortcutPanelState();
}

class _ShortcutPanelState extends State<_ShortcutPanel> {
  /// 正在发送的预设下标；null = 空闲。同一时刻只允许一个在途。
  int? _firing;

  Future<void> _fire(int index) async {
    if (_firing != null) return;
    setState(() => _firing = index);
    final label = kShortcutLabels[index];
    String? error;
    try {
      error = await widget.onFire(kShortcutPresets[index]);
    } catch (e) {
      error = '发送异常：$e';
    }
    if (!mounted) return;
    setState(() => _firing = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '✅ 已发送 $label'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (error == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e2eReady = widget.e2eOk();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('快捷键',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  e2eReady ? '点击即发送到电脑' : '端到端未确认，暂不可用',
                  style: TextStyle(
                    fontSize: 12,
                    color: e2eReady ? cs.outline : cs.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: kShortcutPresets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                // 一行放得下「Ctrl+Shift+Esc 任务管理器」这种长标签
                childAspectRatio: 3.4,
              ),
              itemBuilder: (context, index) {
                final busy = _firing == index;
                final disabled = busy || !e2eReady;
                return FilledButton.tonal(
                  onPressed: disabled ? null : () => _fire(index),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onSecondaryContainer,
                          ),
                        )
                      : Text(
                          kShortcutLabels[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
