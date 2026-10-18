// lib/lab/demos/remotetype/rt_page.dart
//
// RemoteType demo 主页面：两态装配 + 连接编排 + 动作。
//   配对页 —— 优先「统一登录 → 我名下的电脑 → 点一下即连」；
//             服务端没开启统一登录时才退回「选 PC + 填配对 key」
//   输入页 —— 全文同步输入框 + ASR 麦克风 + 端到端指示
//
// 板块拆分（本文件只留装配/状态/连接，其余见各自文件头）：
//   rt_pairing_view.dart   配对页 UI（两态）
//   rt_input_view.dart     输入页 UI
//   rt_connecting_overlay.dart  连接中遮罩
//   rt_text_sync.dart      文本同步管线（composing 挂起/补发 + 防抖）
//
// 语音不再由 demo 内置：用户用手机输入法自带的语音听写，识别文本直接落进
// 输入框，与手动输入共用同一条全文同步管线（原 speech_to_text 已移除）。
//
// 同步触发规则（见 plan §5）：
//   - IME composing 中挂起（拼音中间态不上传），合成结束补发
//   - ASR partial 直发（diff 自愈，实时上屏是特性）
//   - 250ms 防抖

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/remotetype/remotetype.dart';
import '../../../core/line/io/line_orientation.dart';
import '../../../services/remotetype/remotetype_providers.dart';
import '../../../services/remotetype/remotetype_service.dart';
import '../../../core/ui/shell/app_notification.dart';
import '../../../core/theme/context/colors.dart';
import '../../../core/ui/shell/quick_nav_bottom_bar.dart' show bottomBarVisibilityProvider;
import '../../demo_session_host.dart';
import 'rt_constants.dart';
import 'rt_connecting_overlay.dart';
import 'rt_input_view.dart';
import 'rt_pairing_view.dart';
import 'rt_prefs.dart';
import 'rt_session.dart';
import 'rt_shortcut_bar.dart';
import 'rt_text_sync.dart';
import 'rt_touchpad_view.dart';

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
  bool _e2eOk = false;
  bool _connected = false;
  StreamSubscription<RtEvent>? _eventSub;
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

  // 快捷键条（可编排）+ 历史输入 + 托盘显示配置
  List<RtShortcutItem> _shortcuts = kDefaultRtShortcuts();
  List<String> _history = const [];
  String? _firingShortcutId;
  RtBarDisplay _barDisplay = RtBarDisplay.defaults;
  // 重放进行中（连点保护）
  bool _replaying = false;

  // 触摸板模式（v0.6.0+）：页面级内存态，与 enterMode 同待遇不持久化。
  // 横屏只为触摸板服务——进触摸板放开方向锁，退出/离页恢复竖屏
  // （AndroidManifest 全局锁 portrait，这里负责运行期借出与归还）。
  bool _touchpadMode = false;
  double _padSensitivity = kRtPadSensitivityDefault;

  // 文本同步管线（逻辑在 rt_text_sync.dart）
  late final RtTextSync _sync = RtTextSync(
    controller: _textController,
    resolveSession: () => _session,
    isE2eOk: () => _e2eOk,
    enterMode: () => _enterMode,
    onSyncSent: () {
      setState(() => _syncSent += 1);
      _flashSynced();
    },
    persistHistory: (body) async {
      final next = await RtPrefs.pushHistory(body);
      if (mounted) setState(() => _history = next);
    },
    onFlushed: () {
      _textController.clear();
    },
    onNotify: _showSnack,
  );

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(_sync.onControllerChanged);
    _bootstrap();
    unawaited(_loadPrefs());
    // 输入页要全屏手感：本页在场期间压掉主壳底栏（dispose 恢复）。
    // 与 lab_page 的面板隐藏同一条 provider——IndexedStack 同时只可见一页，
    // 单页面模型成立（见 _BottomBarVisibility 注释）。
    ref.read(bottomBarVisibilityProvider.notifier).setHidden(true);
    // 托管重进：host 里有活会话就原地接管（pop 重进不断连）
    _reattachHostedSession();
    // 配对页可见期间轮询在线列表（连上后页面切换，轮询空转开销可忽略）
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_session == null) _refreshClients();
    });
  }

  /// 页面重进：接管 host 上的活会话（不重建连接）。
  ///
  /// 输入框内容是页面态、不随会话走（spec §4 归属切割），重进后为空是预期，
  /// 下一笔输入按全文快照语义自愈。接管到死会话时顺手触发自动重连。
  /// 直接字段赋值不走 setState——此时首帧还没 build。
  void _reattachHostedSession() {
    final hosted = demoSessionHost.get<RtSession>(kRemoteTypeDemoSlug);
    if (hosted == null) return;
    _session = hosted;
    _selectedClient = hosted.targetClientId;
    _eventSub = hosted.events.listen(_onEvent);
    _connected = hosted.isConnected;
    _e2eOk = hosted.e2eConfirmed;
    if (!hosted.isConnected) unawaited(hosted.reconnect());
  }

  Future<void> _loadPrefs() async {
    final shortcuts = await RtPrefs.loadShortcuts();
    final history = await RtPrefs.loadHistory();
    final barDisplay = await RtPrefs.loadBarDisplay();
    final padSensitivity = await RtPrefs.loadTouchpadSensitivity();
    if (!mounted) return;
    setState(() {
      _shortcuts = shortcuts;
      _history = history;
      _barDisplay = barDisplay;
      _padSensitivity = padSensitivity;
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
        final list = await ref.read(remoteTypeServiceProvider).myComputers();
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
    _syncFlashTimer?.cancel();
    _eventSub?.cancel();
    _textController.removeListener(_sync.onControllerChanged);
    _sync.dispose();
    _textController.dispose();
    _keyController.dispose();
    // 底栏与方向锁都归还默认态：本页不在场了，别把主壳锁在自己的偏好里。
    // portraitOnly 与 AndroidManifest 的全局锁一致，无条件恢复是安全的。
    ref.read(bottomBarVisibilityProvider.notifier).setHidden(false);
    unawaited(LineOrientation.portraitOnly());
    // 托管契约：页面退出只 detach，不销毁——会话留给 host，重进原地接管
    // （pop 重进不断连）。显式断开才真正销毁（见 _disconnect 的 host.drop）。
    demoSessionHost.detach(kRemoteTypeDemoSlug);
    super.dispose();
  }

  // ================= 触摸板模式 =================

  /// 进/出触摸板：横竖屏锁只在触摸板期间放开（打字页横屏没意义还晃布局）。
  void _setTouchpadMode(bool on) {
    if (_touchpadMode == on) return;
    setState(() => _touchpadMode = on);
    unawaited(
      on ? LineOrientation.enableAll() : LineOrientation.portraitOnly(),
    );
  }

  // ================= 连接 =================

  /// [keepTypingUi]：重连时保留输入页（不把 `_session` 置空），失败再回配对。
  Future<void> _connect({bool keepTypingUi = false}) async {
    if (_connecting) return;
    final unified = _unified == true;
    // 不是 final：统一登录路径下密钥由服务端下发，要在这里覆盖掉输入框的内容
    var key = _keyController.text.trim();

    if (_selectedClient == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在列表中选择要连接的电脑')));
      return;
    }
    // 统一登录路径下 key 来自服务端；走到这里还拿不到就是列表过期了，
    // 提示刷新比让用户去填一个他不知道的 key 有用得多。
    if (!unified && key.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入配对 key')));
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
      final grant = await ref.read(remoteTypeServiceProvider).ensureGrant();
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _connecting = false;
        if (keepTypingUi) _session = null;
        _error = e.message;
      });
      return;
    } catch (e) {
      await session.dispose();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        if (keepTypingUi) _session = null;
        _error = '连接失败：$e';
      });
      return;
    }

    // 挂到 host 托管：页面退出（detach）后会话继续存活，重进原地接管；
    // 回前台由 host 广播 → session.reconnect() 自动重连。钩子闭包只碰
    // session，页面不在场（detached）也能安全触发。
    demoSessionHost.attach(
      kRemoteTypeDemoSlug,
      () => session,
      onDispose: () => session.dispose(),
      onAppForeground: () => session.reconnect(),
    );
    // 连接期间页面已退出：会话已托管不算孤儿，UI 下次进页接管
    if (!mounted) return;
    _eventSub = session.events.listen(_onEvent);
    _sync.resetHint();
    setState(() {
      _session = session;
      _connecting = false;
      _connected = true;
      _e2eOk = false;
    });
  }

  /// 断开并回到配对页（对齐原型 nav「断开」）。
  ///
  /// 与页面退出（dispose→detach，会话存活）不同：这是**显式销毁**，
  /// 唯一入口是 host.drop。
  void _disconnect() {
    _eventSub?.cancel();
    _eventSub = null;
    unawaited(demoSessionHost.drop(kRemoteTypeDemoSlug));
    _session = null;
    _sync.cancelPending();
    _sync.resetHint();
    _syncFlashTimer?.cancel();
    setState(() {
      _connected = false;
      _e2eOk = false;
      _syncFlash = false;
      _syncSent = 0;
    });
  }

  /// 保持输入页，拆旧会话后重连（对齐原型：overlay 盖在输入页上，不闪回配对）。
  Future<void> _reconnect() async {
    if (_selectedClient == null || _connecting) return;
    _sync.cancelPending();
    _sync.resetHint();
    _syncFlashTimer?.cancel();

    final oldSub = _eventSub;
    _eventSub = null;
    setState(() {
      _connected = false;
      _e2eOk = false;
      _syncFlash = false;
    });
    // 旧会话的销毁归 host.drop（托管契约：销毁只有这一个入口）；
    // `_session` 暂不置空，避免 body 闪回配对页。
    try {
      await oldSub?.cancel();
    } catch (_) {}
    try {
      await demoSessionHost.drop(kRemoteTypeDemoSlug);
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
        _sync.cancelE2eHint();
        setState(() => _e2eOk = true);
      case RtEventKind.connected:
        setState(() => _connected = true);
      case RtEventKind.disconnected:
        // willRetry：socket 死了但会话在自动重连——只把 chips 灰掉，不弹提示；
        // 重试那一次也失败（willRetry=false）才是最终断开，那时才打扰用户。
        setState(() => _connected = false);
        if (!e.willRetry) {
          AppNotification.show(
            context,
            '连接断开（${e.detail ?? ''}）',
            type: AppNotificationType.error,
          );
        }
      case RtEventKind.deliveryFailed:
        AppNotification.show(
          context,
          e.detail ?? '投递失败',
          type: AppNotificationType.error,
        );
      case RtEventKind.error:
        AppNotification.show(
          context,
          e.detail ?? '未知错误',
          type: AppNotificationType.error,
        );
    }
  }

  // ================= 快捷键 / 历史 =================

  /// 发送快捷键（v2：序列宏）。
  ///
  /// 每条 RtShortcutItem 是 `chords + intervalMs`；按序列遍历、各 chord 之间
  /// 睡 `intervalMs`，0 表示立即接龙。后端协议仍是单 hotkey 信封，循环发
  /// 即可，不改 mn-rt。
  ///
  /// **根因修复注**：旧 UI 在 `!_e2eOk` 时整表禁用——端到端只靠文字同步 ACK
  /// 解锁，用户连上后直接点快捷键会一直灰掉，表现为「快捷键不生效」。
  /// 快捷键与全文共用加密路径，WS 已连接即可发。
  Future<void> _fireShortcut(RtShortcutItem item) async {
    if (_firingShortcutId != null) return;
    final session = _session;
    if (session == null || !_connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未连接电脑')));
      return;
    }
    // Win+L 等锁屏类：条上一点即发，误触代价高，先确认。
    // 锁屏判定：序列里有任何 chord 是 ['win','l'] 都拦截。
    final hasLockChord = item.chords.any(
      (c) =>
          c.keys.length == 2 && c.keys.first == 'win' && c.keys.last == 'l',
    );
    if (hasLockChord) {
      final ok = await showRtLockConfirm(context: context, item: item);
      if (!ok || !mounted) return;
    }
    setState(() => _firingShortcutId = item.id);
    String? error;
    try {
      for (var i = 0; i < item.chords.length; i++) {
        if (i > 0 && item.intervalMs > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: item.intervalMs),
          );
          if (!mounted) return; // 异步期间页面退出
        }
        final chordKeys = item.chords[i].keys;
        final sent = await session.syncHotkey(chordKeys);
        if (sent) {
          if (mounted) setState(() => _syncSent += 1);
        } else {
          error = '发送失败（连接已断开？）';
          break;
        }
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
    // 列表编排：删 / 加 / 排序均直接作用在 `_shortcuts` 上；保存走
    // RtPrefs.saveShortcuts。
    final next = await showRtShortcutListEditor(
      context: context,
      current: _shortcuts,
    );
    if (next == null || !mounted) return;
    await RtPrefs.saveShortcuts(next);
    if (!mounted) return;
    setState(() => _shortcuts = next);
  }

  Future<void> _openBarDisplay() async {
    final next = await showRtBarDisplaySheet(
      context: context,
      current: _barDisplay,
    );
    if (next == null || !mounted) return;
    await RtPrefs.saveBarDisplay(next);
    if (!mounted) return;
    setState(() => _barDisplay = next);
  }

  /// 重放当前输入框全文。
  ///
  /// 场景：PC 端焦点丢了，之前的注入没落进目标框；用户把焦点点回去后用这个
  /// 原样重打。协议是全文快照 + mirror diff（mn-rt rt-align.js：mirror 相同
  /// 则 planTransition 为空 → no-op），**原样重发会被判成无变化**，所以先发
  /// 空快照把 mirror 清零，再重发全文——两步直发 session（不过 _sync 管线，
  /// 避免它成功后清空输入框 / 触发历史入库）。
  Future<void> _replayText() async {
    if (_replaying) return;
    final session = _session;
    if (session == null || !_connected) {
      _showSnack('未连接电脑');
      return;
    }
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showSnack('输入框为空，没有可重放的内容');
      return;
    }
    setState(() => _replaying = true);
    String? error;
    try {
      // ① 空快照：PC 端 diff 出 backspace 计划，把 mirror（上次注入内容）
      //    清零。焦点此刻在目标框时正好清掉残留；不在时与协议的固有前提
      //    一致（注入永远落在当前焦点框）。
      final cleared = await session.syncText('');
      final resent = cleared ? await session.syncText(text) : false;
      if (!resent) {
        error = '发送失败（连接已断开？）';
      } else {
        setState(() => _syncSent += 2);
        _flashSynced();
      }
    } catch (e) {
      error = '重放异常：$e';
    }
    if (!mounted) return;
    setState(() => _replaying = false);
    if (error != null) _showSnack(error);
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
    _sync.scheduleSync();
  }

  // ================= UI 装配 =================

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    // 对齐原型 --bg / --card：页底走 tray（surfaceContainerHighest），
    // 浮卡走 surface；禁止 M3 elevation surfaceTint 把奶油卡染成 sage。
    final pageBg = cs.surfaceContainerHighest;
    // 触摸板模式不要 AppBar：手势面全出血，退出/灵敏度都在页内浮层。
    return Scaffold(
      // 键盘不压缩页面：输入框固定高度，键盘直接覆盖底部（与网页控制台一致）。
      // 配对页自行用 viewInsets 兜底（见 RtPairingView）。
      resizeToAvoidBottomInset: false,
      backgroundColor: pageBg,
      appBar: _touchpadMode ? null : _buildTypingAppBar(pageBg),
      body: _session == null || !_touchpadMode
          ? Stack(
              children: [
                _session == null
                    ? RtPairingView(
                        unified: _unified,
                        readiness: _readiness,
                        error: _error,
                        connecting: _connecting,
                        clientsLoading: _clientsLoading,
                        clients: _clients,
                        computers: _computers,
                        selectedClient: _selectedClient,
                        keyController: _keyController,
                        onRefresh: _refreshClients,
                        onSelectClient: (cid) =>
                            setState(() => _selectedClient = cid),
                        onConnect: _connect,
                      )
                    : RtInputView(
                        controller: _textController,
                        enterMode: _enterMode,
                        onEnterModeChanged: (mode) {
                          setState(() => _enterMode = mode);
                          _sync.scheduleSync();
                        },
                        syncFlash: _syncFlash,
                        onClear: () {
                          _textController.clear();
                          setState(() {});
                        },
                        onReplay: _replayText,
                        onComposerTapOutside: _sync.scheduleSync,
                        onTextChanged: () => setState(() {}),
                        shortcuts: _shortcuts,
                        barDisplay: _barDisplay,
                        connected: _connected,
                        firingId: _firingShortcutId,
                        onFire: _fireShortcut,
                        onEdit: _editShortcuts,
                        onHistory: _openHistory,
                        onBarDisplay: _openBarDisplay,
                      ),
                if (_connecting) RtConnectingOverlay(label: _connectingLabel()),
              ],
            )
          : RtTouchpadView(
              session: _session,
              connected: _connected,
              sensitivity: _padSensitivity,
              onSensitivityChanged: (v) {
                _padSensitivity = v;
                unawaited(RtPrefs.saveTouchpadSensitivity(v));
              },
              onExit: () => _setTouchpadMode(false),
              onNotify: _showSnack,
            ),
    );
  }

  PreferredSizeWidget _buildTypingAppBar(Color pageBg) {
    return AppBar(
      title: const Text('远程输入'),
      backgroundColor: pageBg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [
        if (_session != null)
          IconButton(
            icon: const Icon(Icons.touch_app_outlined),
            tooltip: '触摸板',
            onPressed: _connected
                ? () => _setTouchpadMode(true)
                : null, // 未连接时置灰：触摸板没有连接毫无意义
          ),
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
    );
  }

  /// 连接遮罩上的目标名：优先我名下电脑的 label，否则退回 clientId / 「电脑」。
  String _connectingLabel() {
    String label = '电脑';
    if (_selectedClient != null) {
      final matched = _computers.where((x) => x.clientId == _selectedClient);
      if (matched.isNotEmpty) {
        label = matched.first.label;
      } else {
        label = _selectedClient!;
      }
    }
    return label;
  }
}
