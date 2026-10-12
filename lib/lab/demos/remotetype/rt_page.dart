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
import '../../../widgets/context_colors.dart';
import 'rt_constants.dart';
import 'rt_prefs.dart';
import 'rt_session.dart';
import 'rt_shortcut_bar.dart';

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
  // 输入框内「已同步」轻闪（对齐原型 composer sync flash）
  bool _syncFlash = false;
  Timer? _syncFlashTimer;
  // 回车注入方式：'enter'=发送（电脑端敲普通 Enter）/ 'shift_enter'=换行
  // （电脑端敲 Shift+Enter，微信等「Enter=发送」的框里只换行不发送）。
  // 随每条快照下发，可即时切换；页面级内存态（本页其他配置同样不持久化）
  String _enterMode = 'enter';

  // 快捷键条（可编排）+ 历史输入
  List<RtShortcutItem> _shortcuts = kDefaultRtShortcuts();
  List<String> _history = const [];
  String? _firingShortcutId;

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
    unawaited(_loadPrefs());
    // 配对页可见期间轮询在线列表（连上后页面切换，轮询空转开销可忽略）
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_session == null) _refreshClients();
    });
  }

  Future<void> _loadPrefs() async {
    final shortcuts = await RtPrefs.loadShortcuts();
    final history = await RtPrefs.loadHistory();
    if (!mounted) return;
    setState(() {
      _shortcuts = shortcuts;
      _history = history;
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
    _syncFlashTimer?.cancel();
    _eventSub?.cancel();
    _textController.removeListener(_onControllerChanged);
    _textController.dispose();
    _keyController.dispose();
    if (_listening) _stt.stop();
    _session?.dispose();
    super.dispose();
  }

  // ================= 连接 =================

  /// [keepTypingUi]：重连时保留输入页（不把 `_session` 置空），失败再回配对。
  Future<void> _connect({bool keepTypingUi = false}) async {
    if (_connecting) return;
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
          if (keepTypingUi) _session = null;
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
        if (keepTypingUi) _session = null;
        _error = e.message;
      });
      return;
    } catch (e) {
      await session.dispose();
      setState(() {
        _connecting = false;
        if (keepTypingUi) _session = null;
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

  /// 断开并回到配对页（对齐原型 nav「断开」）。
  void _disconnect() {
    _eventSub?.cancel();
    _eventSub = null;
    _session?.dispose();
    _session = null;
    _debounce?.cancel();
    _composingTimer?.cancel();
    _e2eHintTimer?.cancel();
    _syncFlashTimer?.cancel();
    if (_listening) _stt.stop();
    setState(() {
      _connected = false;
      _e2eOk = false;
      _listening = false;
      _e2eHintShown = false;
      _syncFlash = false;
      _syncSent = 0;
    });
  }

  /// 保持输入页，拆旧会话后重连（对齐原型：overlay 盖在输入页上，不闪回配对）。
  Future<void> _reconnect() async {
    if (_selectedClient == null || _connecting) return;
    _debounce?.cancel();
    _composingTimer?.cancel();
    _e2eHintTimer?.cancel();
    if (_listening) _stt.stop();

    final oldSub = _eventSub;
    final oldSession = _session;
    _eventSub = null;
    setState(() {
      _connected = false;
      _e2eOk = false;
      _listening = false;
      _e2eHintShown = false;
      _syncFlash = false;
    });
    // 先 dispose 旧会话，但暂不把 `_session` 置空，避免 body 切回配对页。
    try {
      await oldSub?.cancel();
    } catch (_) {}
    try {
      await oldSession?.dispose();
    } catch (_) {}

    await _connect(keepTypingUi: true);
  }

  void _flashSynced() {
    _syncFlashTimer?.cancel();
    setState(() => _syncFlash = true);
    _syncFlashTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _syncFlash = false);
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
      session.syncText(text, enterMode: _enterMode).then((sent) async {
        if (!mounted) return;
        if (sent) {
          setState(() => _syncSent += 1);
          _flashSynced();
          if (flushAfterSend) {
            final body = text.replaceFirst(RegExp(r'\n+$'), '').trim();
            if (body.isNotEmpty) {
              final next = await RtPrefs.pushHistory(body);
              if (mounted) setState(() => _history = next);
            }
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

  // ================= 快捷键 / 历史 =================

  /// 发送快捷键。
  ///
  /// **根因修复**：旧 UI 在 `!_e2eOk` 时整表禁用——端到端只靠文字同步 ACK
  /// 解锁，用户连上后直接点快捷键会一直灰掉，表现为「快捷键不生效」。
  /// 快捷键与全文共用加密路径，WS 已连接即可发；ACK 同样可确认 e2e。
  Future<void> _fireShortcut(RtShortcutItem item) async {
    if (_firingShortcutId != null) return;
    final session = _session;
    if (session == null || !_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接电脑')),
      );
      return;
    }
    // Win+L 等锁屏类：条上一点即发，误触代价高，先确认。
    final isLock = item.keys.length == 2 &&
        item.keys.first == 'win' &&
        item.keys.last == 'l';
    if (isLock) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('锁屏？'),
          content: Text('将向电脑发送 ${item.label}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('锁屏'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _firingShortcutId = item.id);
    String? error;
    try {
      final sent = await session.syncHotkey(item.keys);
      if (sent) {
        if (mounted) setState(() => _syncSent += 1);
      } else {
        error = '发送失败（连接已断开？）';
      }
    } catch (e) {
      error = '发送异常：$e';
    }
    if (!mounted) return;
    setState(() => _firingShortcutId = null);
    // 常驻条：成功不刷 SnackBar，只报错。
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editShortcuts() async {
    final next = await showRtShortcutEditor(
      context: context,
      current: _shortcuts,
    );
    if (next == null || !mounted) return;
    await RtPrefs.saveShortcuts(next);
    if (!mounted) return;
    setState(() => _shortcuts = next);
  }

  Future<void> _openHistory() async {
    final picked = await showRtHistorySheet(
      context: context,
      history: _history,
      onClear: () async {
        await RtPrefs.clearHistory();
        if (mounted) setState(() => _history = const []);
      },
    );
    if (picked == null || !mounted) return;
    final text = picked;
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _asrBase = text;
    _scheduleSync();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    // 对齐原型 --bg / --card：页底走 tray（surfaceContainerHighest），
    // 浮卡走 surface；禁止 M3 elevation surfaceTint 把奶油卡染成 sage。
    final pageBg = cs.surfaceContainerHighest;
    return Scaffold(
      // 键盘不压缩页面：输入框固定高度，键盘直接覆盖底部（与网页控制台一致）。
      // 配对页自行用 viewInsets 兜底（见 _buildPairing）。
      resizeToAvoidBottomInset: false,
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text('远程输入'),
        backgroundColor: pageBg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (_session != null) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重连',
              onPressed: _connecting ? null : _reconnect,
            ),
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: '断开',
              onPressed: _disconnect,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _session == null ? _buildPairing() : _buildInput(context),
          if (_connecting) _buildConnectingOverlay(),
        ],
      ),
    );
  }

  Widget _buildConnectingOverlay() {
    final c = context.colors;
    final cs = c.scheme;
    String label = '电脑';
    if (_selectedClient != null) {
      final matched = _computers.where((x) => x.clientId == _selectedClient);
      if (matched.isNotEmpty) {
        label = matched.first.label;
      } else {
        label = _selectedClient!;
      }
    }
    return AbsorbPointer(
      child: ColoredBox(
        color: c.text.withValues(alpha: 0.28),
        child: Center(
          child: Material(
            color: c.surface,
            elevation: 8,
            shadowColor: cs.shadow.withValues(alpha: 0.18),
            surfaceTintColor: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '正在连接',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontSize: 13, color: c.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPairing() {
    final c = context.colors;
    final cs = c.scheme;
    // Scaffold 已关 resizeToAvoidBottomInset：这里用 viewInsets 把整块内容
    // 抬到键盘上方，SingleChildScrollView 保证极小屏仍可滚动
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.keyboard_alt_outlined, size: 56, color: c.text),
              const SizedBox(height: 12),
              Text(
                '把手机变成电脑的输入设备',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
              ),
              const SizedBox(height: 24),
              if (_unified == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_unified!)
                // ── 统一登录：我名下的电脑，点一下即连（无显式连接按钮）──
                ...[
                  _sectionHead(
                    title: '我的电脑',
                    onRefresh: _clientsLoading ? null : _refreshClients,
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
                        style: TextStyle(color: c.textMuted),
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
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                  _sectionHead(title: '① 选择电脑', onRefresh: _refreshClients),
                  if (_clients.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _clientsLoading
                            ? '正在获取在线 PC…'
                            : '暂无 PC 上线——请先在电脑上运行 remotetype serve --align',
                        style: TextStyle(color: c.textMuted),
                      ),
                    )
                  else
                    ..._clients.map((cid) {
                      final selected = cid == _selectedClient;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: c.surface,
                          elevation: 1,
                          shadowColor: cs.shadow.withValues(alpha: 0.06),
                          surfaceTintColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () =>
                                setState(() => _selectedClient = cid),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                    color:
                                        selected ? cs.primary : c.textMuted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      cid,
                                      style: const TextStyle(
                                          fontFamily: 'monospace'),
                                    ),
                                  ),
                                  Text(
                                    selected ? '已选' : '在线',
                                    style: TextStyle(
                                        fontSize: 11, color: c.textMuted),
                                  ),
                                ],
                              ),
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
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      hintText: '电脑端 remotetype serve --align 打印的 key',
                      filled: true,
                      fillColor: c.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _connecting ? null : _connect,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(_connecting ? '连接中…' : '实时同步连接'),
                  ),
                ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 28),
              Text(
                _unified == true
                    ? '同一账号自动配对 · 端到端加密\n无需复制 key'
                    : '端到端加密：文本在手机加密、电脑解密，中转服务器只经手密文。\n'
                        'key 即凭据，请勿外传。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: c.textMuted, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHead({required String title, VoidCallback? onRefresh}) {
    final c = context.colors;
    final cs = c.scheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const Spacer(),
          Material(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  '刷新',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一台我名下的电脑。整行可点即连——无显式「连接」按钮（对齐原型 .pc）。
  Widget _buildComputerTile(RtComputer c) {
    final colors = context.colors;
    final cs = colors.scheme;
    final online = c.online;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: online ? 1 : 0.5,
        child: Material(
          color: colors.surface,
          elevation: 1,
          shadowColor: cs.shadow.withValues(alpha: 0.06),
          surfaceTintColor: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: online && !_connecting
                ? () {
                    setState(() => _selectedClient = c.clientId);
                    _connect();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          online
                              ? Icons.desktop_windows
                              : Icons.desktop_access_disabled,
                          size: 22,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      if (online)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.surface, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          c.clientId,
                          style: TextStyle(fontSize: 12, color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    online ? '在线 · 点击连接' : '不在线',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final charCount = _textController.text.characters.length;
    // 对齐原型：composer 固定矮卡，键盘直接盖住底部。
    const double fieldHeight = 148;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEnterSeg(cs),
            const SizedBox(height: 16),
            RtShortcutBar(
              shortcuts: _shortcuts,
              connected: _connected,
              firingId: _firingShortcutId,
              onFire: _fireShortcut,
              onEdit: _editShortcuts,
              onHistory: _openHistory,
            ),
            const SizedBox(height: 16),
            AnimatedScale(
              scale: _syncFlash ? 1.01 : 1.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: Material(
                color: c.surface,
                elevation: _syncFlash ? 3 : 1,
                shadowColor: cs.shadow.withValues(alpha: 0.1),
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: fieldHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          onChanged: (_) => setState(() {}),
                          onTapOutside: (_) {
                            if (_textController.value.composing !=
                                TextRange.empty) {
                              _scheduleSync();
                            }
                          },
                          maxLines: null,
                          expands: true,
                          maxLength: kRtMaxTextLength,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.45,
                            color: c.text,
                          ),
                          cursorColor: cs.primary,
                          // 对齐原型 .composer textarea：无描边、透明底，焦点也不出框。
                          decoration: InputDecoration(
                            hintText: '打字或说话，内容会同步到电脑…',
                            hintStyle: TextStyle(
                              color: c.textMuted.withValues(alpha: 0.7),
                            ),
                            filled: false,
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.fromLTRB(
                                16, 16, 16, 6),
                            counterText: '',
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Row(
                          children: [
                            AnimatedOpacity(
                              opacity: _syncFlash ? 1 : 0,
                              duration: const Duration(milliseconds: 220),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '已同步',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$charCount/$kRtMaxTextLength',
                              style: TextStyle(
                                fontSize: 11,
                                color: c.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: c.surface,
                elevation: 1,
                shadowColor: cs.shadow.withValues(alpha: 0.06),
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    _asrBase = '';
                    _textController.clear();
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    child: Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Center(
              child: Material(
                color: _listening ? cs.tertiary : cs.primary,
                elevation: 4,
                shadowColor: (_listening ? cs.tertiary : cs.primary)
                    .withValues(alpha: 0.3),
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _toggleListening,
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(
                      Icons.mic,
                      size: 26,
                      color: _listening ? cs.onTertiary : cs.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// 全宽滑动分段：发送 / 换行（对齐原型 .seg）。
  Widget _buildEnterSeg(ColorScheme cs) {
    final isEnter = _enterMode == 'enter';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutBack,
                left: isEnter ? 0 : half,
                top: 0,
                bottom: 0,
                width: half,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _segBtn(
                      label: '发送',
                      selected: isEnter,
                      onTap: () {
                        if (_enterMode == 'enter') return;
                        setState(() => _enterMode = 'enter');
                        _scheduleSync();
                      },
                    ),
                  ),
                  Expanded(
                    child: _segBtn(
                      label: '换行',
                      selected: !isEnter,
                      onTap: () {
                        if (_enterMode == 'shift_enter') return;
                        setState(() => _enterMode = 'shift_enter');
                        _scheduleSync();
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segBtn({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? c.scheme.onPrimary : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
