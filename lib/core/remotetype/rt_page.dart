// lib/core/remotetype/rt_page.dart
//
// RemoteType demo 主页面：连接编排 + 按激活布局渲染 + 动作。
//   大厅（连接列表）—— 优先「统一登录 → 我名下的电脑 → 点一下即连」；
//             服务端没开启统一登录时才退回「选 PC + 填配对 key」。
//             常显主壳底栏（钉选后它是主页），AppBar 左侧无返回。
//   详情 —— 全文同步输入框 + 端到端指示。头部只留「返回 + 目标电脑名 +
//             重连」；布局与设置都归左上角一颗胶囊。
//             系统手势/返回键经 PopScope 拦截，与按钮同义（画布编辑→画布使用→
//             详情→大厅）。返回不断连，会话仍托管。
//   布局（可插拔）—— 渲染什么由**激活布局的 kind** 决定，不再是页面级两态：
//             kind=writer（写字，固定形态）→ 写字页；kind=canvas → 画布
//             （触摸板 / 输入框 / 快捷按钮同一模块系统自由编排，use / edit 两态
//             边界明显，见 rt_canvas_view.dart）。
//             每种布局左上角都有同一颗胶囊（见 ui/rt_layout_capsule.dart）：
//             点开即布局面板——第一层是全部布局的列表（快速切换），最下面是
//             「远程输入设置」入口（编排等设置全在设置页）。切到只属另一朝向的
//             布局时直接转屏（竖屏选游戏 → 转横屏），不用自己拧手机。
//             写字页与其它布局平级，没有单独的「返回写字」旁门。
//
// 板块拆分（本文件只留装配/状态/连接，其余见各自文件头）：
//   rt_pairing_view.dart   大厅 UI（两态）
//   rt_input_view.dart     写字页 UI（= 写字布局的固定形态）
//   rt_canvas_view.dart    画布 UI（模块系统 + 编辑态）
//   rt_settings_page.dart  RT 设置（布局管理 + 编排 + 输入偏好）
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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/remotetype/remotetype.dart';
import '../../core/line/io/line_orientation.dart';
import '../../core/nav/nav_entry.dart' show demoNavId;
import '../../services/remotetype/remotetype_providers.dart';
import '../../services/remotetype/remotetype_service.dart';
import '../../core/ui/shell/app_notification.dart';
import '../../core/theme/context/colors.dart';
import '../../core/ui/shell/quick_nav_bottom_bar.dart'
    show QuickNavBottomBar, bottomBarVisibilityProvider;
import '../../lab/demo_session_host.dart';
import 'data/rt_constants.dart';
import 'ui/rt_connecting_overlay.dart';
import 'canvas/template/rt_canvas_presets.dart';
import 'canvas/rt_canvas_view.dart';
import 'settings/rt_settings_page.dart';
import 'ui/rt_input_view.dart';
import 'ui/rt_layout_capsule.dart';
import 'ui/rt_layout_picker.dart';
import 'ui/rt_pairing_view.dart';
import 'data/rt_prefs.dart';
import 'protocol/rt_session.dart';
import 'ui/rt_shortcut_bar.dart';
import 'protocol/rt_text_sync.dart';

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
  // 归 RT 设置管并持久化（RtPrefs）——写字页是固定形态，不再带这颗开关。
  String _enterMode = 'enter';

  // 快捷键条（可编排）+ 历史输入 + 托盘显示配置
  List<RtShortcutItem> _shortcuts = kDefaultRtShortcuts();
  List<String> _history = const [];
  String? _firingShortcutId;
  RtBarDisplay _barDisplay = RtBarDisplay.defaults;
  // 重放进行中（连点保护）
  bool _replaying = false;

  // 横屏画布模式（触摸板/输入框/键盘/按钮同一画布编排，详见 rt_canvas_view.dart）：
  // 不再用页面级布尔态切两套写死的页面——当前渲染什么由**激活布局的 kind**
  // 决定（canvas → 画布；writer → 写字页）。横竖屏各有一套激活布局，
  // 互不串台（见 rt_prefs 的 RtCanvasLayouts）。
  // 画布编辑子态（use/edit）：纯画布内部状态，不锁方向、不动底栏。
  bool _canvasEdit = false;

  /// 跨朝向「修改」时钉住的编辑朝向：OS 旋转到位前 MediaQuery 仍是旧朝向，
  /// 若仍按设备朝向取 active，会改到错误的一侧。编辑结束清空。
  String? _editBindOrientation;

  /// 设置页点「在画布上编辑」记下的目标布局 id：设置页刚关时先回读盘上
  /// 最新布局集，再执行编辑——用旧快照回写会抹掉设置页刚做的改动。
  String? _pendingEditLayoutId;

  double _padSensitivity = kRtPadSensitivityDefault;
  // 画布布局（模块锚点 + 按钮位）：跨会话记住，持久化（RtPrefs）。
  // 画布布局集（横竖两朝向 + 各自激活）：跨会话记住，持久化。横竖屏布局
  // 相互隔离——各有各的列表分组与激活位。首跑空表：用代码内置铺一份；
  // 之后用户编辑/复制/删除/切换都落盘。
  RtCanvasLayouts _layouts = const RtCanvasLayouts(
    list: kRtCanvasBuiltinPresets,
    activeId: kRtCanvasPresetTouchpad,
  );

  /// 当前朝向的激活布局条目（横竖屏各一套，隔离）。
  RtCanvasNamedLayout? get _activeEntry => _layouts.activeFor(
    _canvasOrientation,
  );

  /// 当前是否渲染画布：激活布局 kind=canvas。写字布局（kind=writer）走
  /// 输入页——写字页是「布局之一」，不是页面级的另一套固定形态。
  bool get _inCanvasLayout =>
      (_activeEntry?.kind ?? RtLayoutKind.canvas) == RtLayoutKind.canvas;

  /// 画布当前朝向（跟随设备旋转；MediaQuery 驱动重建时刷新）。
  /// 编辑态若钉了 [_editBindOrientation]，优先用钉住的（跨朝向修改未转完屏时）。
  String get _canvasOrientation {
    if (_canvasEdit && _editBindOrientation != null) {
      return _editBindOrientation!;
    }
    return MediaQuery.orientationOf(context) == Orientation.landscape
        ? kRtCanvasOrientLandscape
        : kRtCanvasOrientPortrait;
  }

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
    // 托管重进：host 里有活会话就原地接管（pop 重进不断连）
    _reattachHostedSession();
    // 底栏显隐随页面状态同步：大厅（连接列表）常显，详情/画布全程隐藏。
    // 请求按本页 nav id 记名——IndexedStack 里钉选页 State 全部常驻，
    // 裸 bool 会把本页的请求泄漏到其它钉选页（provider 注释）。
    _syncBottomBar();
    // 配对页可见期间轮询在线列表（连上后页面切换，轮询空转开销可忽略）
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_session == null) _refreshClients();
    });
  }

  /// 接管 host 上的活会话（不重建连接）。两个入口：
  /// initState 页面重进（直接字段赋值，首帧还没 build，不走 setState）；
  /// _connect 的同目标托管分支（调用方随后 setState 刷 UI）。
  ///
  /// 输入框内容是页面态、不随会话走（spec §4 归属切割），重进后为空是预期，
  /// 下一笔输入按全文快照语义自愈。接管到死会话时顺手触发自动重连。
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
    // 回车注入方式（发送 / 换行）：归 RT 设置管，写字页不再带这颗开关。
    final enterMode = await RtPrefs.loadEnterMode();
    var layouts = await RtPrefs.loadCanvasLayouts();
    // 持久化空（首跑或新装）：不写盘，只在内存里铺内置——首次编辑/切换
    // / 复制再落盘，避免每启动都触发一次 SharedPreferences 写入。
    if (layouts.list.isEmpty) {
      layouts = const RtCanvasLayouts(
        list: kRtCanvasBuiltinPresets,
        activeId: kRtCanvasPresetTouchpad,
      );
      // 首跑内存铺内置：修订号一并写上，避免下次启动误触发出厂覆盖。
      unawaited(
        RtPrefs.saveCanvasBuiltinFactoryRev(kRtCanvasBuiltinFactoryRev),
      );
    } else {
      // 缺内置 → 补齐；出厂修订落后 → 强制用新工厂覆盖内置（自定义保留）。
      final factoryRev = await RtPrefs.loadCanvasBuiltinFactoryRev();
      final ensured = rtEnsureBuiltinPresets(
        layouts,
        persistedFactoryRev: factoryRev,
      );
      if (!identical(ensured, layouts)) {
        layouts = ensured;
        unawaited(RtPrefs.saveCanvasLayouts(layouts));
      }
      if (factoryRev < kRtCanvasBuiltinFactoryRev) {
        unawaited(
          RtPrefs.saveCanvasBuiltinFactoryRev(kRtCanvasBuiltinFactoryRev),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _shortcuts = shortcuts;
      _history = history;
      _barDisplay = barDisplay;
      _padSensitivity = padSensitivity;
      _enterMode = enterMode;
      _layouts = layouts;
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
    // 画布在手柄使用中退出：尽力释放虚拟手柄（会话仍托管，WS 活着就能送达）。
    if (_vpadReady != null) unawaited(_releaseVpad());
    _pollTimer?.cancel();
    _syncFlashTimer?.cancel();
    _eventSub?.cancel();
    _textController.removeListener(_sync.onControllerChanged);
    _sync.dispose();
    _textController.dispose();
    _keyController.dispose();
    // 底栏与方向锁都归还默认态：本页不在场了，别把主壳锁在自己的偏好里。
    // portraitOnly 与 AndroidManifest 的全局锁一致，无条件恢复是安全的。
    ref.read(bottomBarVisibilityProvider.notifier).setHidden(null);
    unawaited(LineOrientation.portraitOnly());
    // 托管契约：页面退出只 detach，不销毁——会话留给 host，重进原地接管
    // （pop 重进不断连）。host 主动销毁的入口是 _connect 切目标电脑分支。
    demoSessionHost.detach(kRemoteTypeDemoSlug);
    super.dispose();
  }

  // ================= 触摸板模式 =================

  /// 设备真实朝向（不看编辑钉住值）——跨朝向「修改」算目标侧时用。
  String get _deviceOrientation =>
      MediaQuery.orientationOf(context) == Orientation.landscape
      ? kRtCanvasOrientLandscape
      : kRtCanvasOrientPortrait;

  /// 进/出画布编辑子态：纯画布内部状态，方向锁与底栏不动。
  void _setCanvasEdit(bool on) {
    if (_canvasEdit == on &&
        (on || _editBindOrientation == null)) {
      return;
    }
    setState(() {
      _canvasEdit = on;
      if (!on) _editBindOrientation = null;
    });
  }

  /// 激活布局的内容变更（拖动落位 / 缩放 / 显隐 / 模块开关）：先落 state
  /// 再异步落盘（失败不回滚——下次进页读盘仍旧位）。只动当前朝向的激活
  /// 布局——横竖屏配置互不串台。编辑态用 [_canvasOrientation]（可含钉住朝向）。
  void _setActiveLayout(RtCanvasLayout layout) {
    final next = _layouts.withUpdatedActiveFor(_canvasOrientation, layout);
    setState(() => _layouts = next);
    unawaited(RtPrefs.saveCanvasLayouts(next));
  }

  /// 切布局：按目标布局的朝向激活，并**同步屏幕方向**——用户不必自己转屏，
  /// 选完即到位：
  ///   · 目标布局在当前朝向可用 → 就地激活，方向不动（触控屏这类双朝向的）；
  ///   · 目标布局只属另一朝向 → 激活到那一侧，并把屏幕转过去（竖屏选游戏 →
  ///     直接转横屏；横屏选写字 → 直接转竖屏）。
  void _switchLayout(String id) {
    RtCanvasNamedLayout? entry;
    for (final p in _layouts.list) {
      if (p.id == id) {
        entry = p;
        break;
      }
    }
    if (entry == null) return;
    // 用设备朝向判断「就地可用」，避免编辑钉住朝向干扰普通切换。
    final current = _deviceOrientation;
    final usableHere = rtCanvasLayoutUsableIn(current, entry);
    final targetOrient = usableHere ? current : entry.orientation;
    final next = _layouts.withActiveFor(targetOrient, id);
    if (!identical(next, _layouts)) {
      setState(() => _layouts = next);
      unawaited(RtPrefs.saveCanvasLayouts(next));
    }
    _applyLayoutOrientation(entry);
  }

  /// 从设置「修改」进编辑：激活目标侧、钉住朝向、await 落盘、转屏、开编辑。
  /// 竖屏点横屏布局时，旋转完成前仍渲染/写入目标侧，不会改到竖屏激活。
  Future<void> _beginEditLayout(String id) async {
    RtCanvasNamedLayout? entry;
    for (final p in _layouts.list) {
      if (p.id == id) {
        entry = p;
        break;
      }
    }
    if (entry == null || !entry.editable) return;
    final device = _deviceOrientation;
    final usableHere = rtCanvasLayoutUsableIn(device, entry);
    final targetOrient = usableHere ? device : entry.orientation;
    final next = _layouts.withActiveFor(targetOrient, id);
    setState(() {
      _layouts = next;
      _editBindOrientation = targetOrient;
      _canvasEdit = true;
    });
    await RtPrefs.saveCanvasLayouts(next);
    if (!mounted) return;
    _applyLayoutOrientation(entry);
  }

  /// 屏幕方向跟随布局：写字页只属竖屏 → 锁竖屏；锁横屏的布局（轮盘 / 手柄 /
  /// 键盘）→ 直接转横屏；双朝向布局（触控屏）→ 放开旋转，保持当前朝向。
  void _applyLayoutOrientation(RtCanvasNamedLayout entry) {
    if (entry.kind == RtLayoutKind.writer) {
      unawaited(LineOrientation.portraitOnly());
      return;
    }
    if (rtCanvasLayoutLocksLandscape(entry.data)) {
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      return;
    }
    unawaited(LineOrientation.enableAll());
  }

  /// 共享头部（所有布局共用）：返回小圆按钮 + 布局胶囊。
  ///
  /// 内置（游戏 / 键盘 / 触控屏）、内置固定（写字）、用户自定义——一律
  /// 走这一份，页面级浮层，画布与写字页长得一样。胶囊点开是布局面板：
  /// 第一层全部布局的列表，最下面是「远程输入设置」入口。
  ///
  /// 高度 [kRtSharedHeaderHeight]，写字页内容按它让位（画布是全出血，
  /// 头部浮在画布左上角，和原来的胶囊一个位置）。
  Widget _sharedHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              RtRoundIconButton(
                icon: Icons.arrow_back_ios_new,
                tooltip: '返回连接列表',
                onTap: _exitDetail,
              ),
              const SizedBox(width: 8),
              RtLayoutCapsule(
                connected: _connected,
                layoutName: _activeEntry?.name ?? '写字',
                onOpen: _openLayoutPicker,
              ),
              const Spacer(),
              RtRoundIconButton(
                icon: Icons.refresh_rounded,
                tooltip: '重连',
                onTap: _connecting ? () {} : _reconnect,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开布局切换面板（竖屏页头 / 横屏左上角共用）：第一层是布局列表，
  /// 底下附一个「远程输入设置」入口。
  Future<void> _openLayoutPicker() async {
    await showRtLayoutPicker(
      context,
      layouts: _layouts,
      orientation: _canvasOrientation,
      activeId: _activeEntry?.id ?? '',
      onPick: _switchLayout,
      onOpenSettings: _openSettings,
    );
  }

  /// 打开 RT 设置页（布局编排 + 回车方式 + 灵敏度 + 快捷键）。关掉后回读
  /// 布局与回车方式——设置页自己落盘，页面态要跟着回读。
  ///
  /// 设置页里点「在画布上编辑」只记下目标 id：等设置页关掉、布局回读
  /// 完毕再执行编辑，避免拿设置页改动前的旧快照回写磁盘。
  Future<void> _openSettings() async {
    await showRtSettingsPage(
      context,
      // 有会话即可「修改」任意可编辑布局（含跨朝向自动转向）；不限当前已在画布。
      onEditCanvasLayout: _session != null
          ? (id) {
              _pendingEditLayoutId = id;
            }
          : null,
    );
    if (!mounted) return;
    await _reloadPrefs();
    if (!mounted) return;
    final pending = _pendingEditLayoutId;
    if (pending == null) return;
    _pendingEditLayoutId = null;
    await _beginEditLayout(pending);
  }

  /// 重读持久化偏好（设置页改动后回读布局 / 回车方式）。
  Future<void> _reloadPrefs() async {
    var layouts = await RtPrefs.loadCanvasLayouts();
    if (layouts.list.isEmpty) {
      layouts = const RtCanvasLayouts(
        list: kRtCanvasBuiltinPresets,
        activeId: kRtCanvasPresetTouchpad,
      );
    } else {
      layouts = rtEnsureBuiltinPresets(
        layouts,
        persistedFactoryRev: await RtPrefs.loadCanvasBuiltinFactoryRev(),
      );
    }
    final enterMode = await RtPrefs.loadEnterMode();
    if (!mounted) return;
    setState(() {
      _layouts = layouts;
      _enterMode = enterMode;
    });
  }

  // ================= 底栏显隐 / 横屏手柄 / 返回大厅 =================

  /// 底栏隐匿请求同步：详情（打字）页全程无底栏（沉浸），横屏画布亦然
  /// （都有 `_session`）；只有大厅（连接列表）常显——它是钉选后的主页，
  /// 藏了就没法导航。请求按本页 nav id 记名，切到其它钉选页时主壳不生效。
  void _syncBottomBar() {
    final hide = _session != null;
    ref
        .read(bottomBarVisibilityProvider.notifier)
        .setHidden(hide ? demoNavId(kRemoteTypeDemoSlug) : null);
  }

  /// 返回连接大厅：会话不销毁——仍托管在 host（销毁入口是 host.drop），
  /// 输入框内容也留在页面态。再点同一台电脑原地接管秒回输入页（见 _connect
  /// 开头的托管分支）。
  void _exitDetail() {
    // 重连进行中不响应返回：_connect 完成回调会把会话写回 `_session`，
    // 中途退出会被拽回输入页；等这波重连落地再返回。
    if (_connecting) return;
    final wasImmersive = _inCanvasLayout;
    _eventSub?.cancel();
    _eventSub = null;
    if (wasImmersive) unawaited(_releaseVpad());
    setState(() {
      _session = null;
      _canvasEdit = false;
      _editBindOrientation = null;
    });
    _syncBottomBar();
    // 非常规路径（AppBar 返回只在大厅/详情可达，理论摸不到）兜底：
    // 带着横屏借出走大厅的话，把竖屏锁还回去。
    if (wasImmersive) unawaited(LineOrientation.portraitOnly());
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

    // 返回大厅后同目标会话还在托管：原地接管直接回输入页，不重连（接管与
    // 页面重进同一条路径，含死会话自动重连）。
    final hosted = demoSessionHost.get<RtSession>(kRemoteTypeDemoSlug);
    if (hosted != null && hosted.targetClientId == _selectedClient) {
      _reattachHostedSession();
      setState(() {});
      _syncBottomBar(); // 大厅 → 详情，底栏隐匿随 `_session` 翻转
      return;
    }
    // 换了目标电脑：旧托管会话显式销毁——host.attach 契约是「有则复用绝不
    // 重建」，不 drop 的话新会话挂不进托管，成了脱管孤儿连接。
    if (hosted != null) {
      await demoSessionHost.drop(kRemoteTypeDemoSlug);
      if (!mounted) return;
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
        _syncBottomBar(); // 重连失败回大厅时归还底栏
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
      _syncBottomBar(); // 重连失败回大厅时归还底栏
      return;
    } catch (e) {
      await session.dispose();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        if (keepTypingUi) _session = null;
        _error = '连接失败：$e';
      });
      _syncBottomBar(); // 重连失败回大厅时归还底栏
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
    _syncBottomBar(); // 大厅 → 详情，底栏隐匿随 `_session` 翻转
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
        // 断线期间 PC agent 可能重启（vpad 句柄失效）：重置初始化链，
        // 下一条 vpad 指令会重新 release_all + init。
        _vpadReady = null;
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
      (c) => c.keys.length == 2 && c.keys.first == 'win' && c.keys.last == 'l',
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
          await Future<void>.delayed(Duration(milliseconds: item.intervalMs));
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

  // ================= 虚拟手柄（vpad_* 协议） =================

  /// vpad 句柄：手机是 PC 虚拟手柄的唯一客户端，句柄固定 pad1（init 前
  /// 先 release_all 清残留，rust 端 next_index 从 1 起 → init 必得 pad1）。
  static const String _vpadHandle = 'pad1';

  /// 懒初始化链：首次 vpad 指令时 release_all + init（不用进画布就 init
  /// ——ViGEmBus 缺失时 init 会触发 PC 弹 UAC，不能在画布入口就惊扰）。
  Future<bool>? _vpadReady;

  /// 发送一条 vpad 指令；首次调用先跑初始化链（release_all → init pad1）。
  Future<void> _sendVpad(Map<String, dynamic> cmd) async {
    if (_session == null || !_connected) return;
    _vpadReady ??= _bootstrapVpad();
    await _vpadReady;
    await _vpadRaw(cmd);
  }

  /// 不做初始化链的裸发送（初始化/释放自己就是链上的一环，避递归）。
  Future<bool> _vpadRaw(Map<String, dynamic> cmd) async {
    final session = _session;
    if (session == null || !_connected) return false;
    return session.syncVpad(cmd);
  }

  Future<bool> _bootstrapVpad() async {
    await _vpadRaw({'action': 'vpad_release_all'});
    return _vpadRaw({'action': 'vpad_init', 'vpad_slot': 1});
  }

  /// 退出画布 / 页面销毁时释放手柄（等初始化链落地再放，防 release 抢跑）。
  Future<void> _releaseVpad() async {
    final ready = _vpadReady;
    _vpadReady = null;
    if (ready != null) await ready;
    await _vpadRaw({'action': 'vpad_release', 'vpad_handle': _vpadHandle});
  }

  /// 手柄键区按键 → vpad_button / vpad_trigger（扳机按压 = 行程 1.0/0.0）。
  void _onVpadKey({String? button, String? trigger, required bool pressed}) {
    if (button != null) {
      unawaited(
        _sendVpad({
          'action': 'vpad_button',
          'vpad_handle': _vpadHandle,
          'vpad_button': button,
          'vpad_value_bool': pressed,
        }),
      );
    } else if (trigger != null) {
      unawaited(
        _sendVpad({
          'action': 'vpad_trigger',
          'vpad_handle': _vpadHandle,
          'vpad_trigger': trigger,
          'vpad_value': pressed ? 1.0 : 0.0,
        }),
      );
    }
  }

  // ================= 虚拟键盘（按键即发 hotkey） =================

  /// 画布键盘模块一次按键（修饰键已粘滞合成进 chord）→ hotkey 通道。
  /// 与快捷键条同一 syncHotkey 路径；Win+L 之类锁屏组合与条上同规，先确认。
  Future<void> _onKbChord(List<String> keys) async {
    final session = _session;
    if (session == null || !_connected) {
      _showSnack('未连接电脑');
      return;
    }
    final isLock = keys.length == 2 && keys.first == 'win' && keys.last == 'l';
    if (isLock) {
      final ok = await showRtLockConfirm(
        context: context,
        item: RtShortcutItem(
          id: 'kb-win-l',
          label: 'Win+L',
          chords: [RtChord(keys: keys)],
          intervalMs: 0,
        ),
      );
      if (!ok || !mounted) return;
    }
    final sent = await session.syncHotkey(keys);
    if (!mounted) return;
    if (sent) {
      setState(() => _syncSent += 1);
    } else {
      _showSnack('发送失败（连接已断开？）');
    }
  }

  // ================= UI 装配 =================

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    // 对齐原型 --bg / --card：页底走 tray（surfaceContainerHighest），
    // 浮卡走 surface；禁止 M3 elevation surfaceTint 把奶油卡染成 sage。
    final pageBg = cs.surfaceContainerHighest;
    // 底栏只在大厅在场：详情页全程无底栏（沉浸），给内容留出的
    // 浮层高度也一并撤掉；键盘弹出时主壳收起底栏，预留同步撤掉。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final barShown = _session == null && keyboard == 0;
    // 画布模式不要 AppBar：全出血，编辑/退出/显隐都在画布浮层。
    // 渲染什么由激活布局的 kind 决定：canvas → 画布；writer → 写字页。
    final canvasMode = _session != null && _inCanvasLayout;
    Widget body;
    if (canvasMode) {
      body = RtCanvasView(
        session: _session,
        connected: _connected,
        sensitivity: _padSensitivity,
        onSensitivityChanged: (v) {
          _padSensitivity = v;
          unawaited(RtPrefs.saveTouchpadSensitivity(v));
        },
        textController: _textController,
        shortcuts: _shortcuts,
        firingId: _firingShortcutId,
        activeLayout: _activeEntry?.data ?? const RtCanvasLayout(),
        activeId: _activeEntry?.id ?? '',
        // 输入页模块 = 连接后落到的打字页本体（同一份 props，竖屏默认布局
        // 的唯一模块；放进任意布局即整页打字面）。
        composerModule: RtInputView(
          controller: _textController,
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
        editMode: _canvasEdit,
        onLayoutChanged: _setActiveLayout,
        onDirection: (dir) => unawaited(
          _sendVpad({
            'action': 'vpad_dpad',
            'vpad_handle': _vpadHandle,
            'vpad_dir': dir ?? 'none',
          }),
        ),
        onVpadKey: _onVpadKey,
        onStickAxis: (axis, value) => unawaited(
          _sendVpad({
            'action': 'vpad_axis',
            'vpad_handle': _vpadHandle,
            'vpad_axis': axis,
            'vpad_value': value,
          }),
        ),
        onKbChord: (keys) => unawaited(_onKbChord(keys)),
        onEditModeChanged: _setCanvasEdit,
        onFire: (item) => unawaited(_fireShortcut(item)),
        onEditShortcuts: _editShortcuts,
        onNotify: _showSnack,
      );
    } else {
      body = Stack(
        children: [
          // Positioned.fill：Stack 默认 loose fit 会让写字页收缩到内容最小宽
          // （托盘标题行 ~148px），输入框被挤成窄条——铺满才对。
          Positioned.fill(
            child: _session == null
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
                : Padding(
                    // 给共享头部让位（头部是页面级浮层，压在内容之上）。
                    padding: const EdgeInsets.only(
                      top: kRtSharedHeaderHeight,
                    ),
                    child: RtInputView(
                      controller: _textController,
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
                  ),
          ),
          if (_connecting) RtConnectingOverlay(label: _connectingLabel()),
        ],
      );
    }
    // 共享头部：所有布局（内置 / 内置固定 / 自定义）共用这一组控件——
    // 画布与写字页长一个样，浮在内容之上。
    if (_session != null) {
      body = Stack(
        children: [
          body,
          _sharedHeader(),
        ],
      );
    }
    if (barShown) {
      body = Padding(
        padding: EdgeInsets.only(
          bottom: QuickNavBottomBar.bodyBottomReserve(context),
        ),
        child: body,
      );
    }
    // 系统返回（手势/返回键）逐层退出：画布编辑→画布使用→详情→大厅。
    // 本页是壳根钉选页（IndexedStack 常驻），pop 根路由 = 退出应用——
    // 只有大厅态放行 pop（Android 根页惯例）。_exitDetail 内部挡
    // _connecting：重连进行中返回不响应，防 _connect 完成回调拽回输入页。
    // 画布不再有「返回写字」旁门：写字页与其它布局平级，想回去从胶囊的
    // 布局列表里切即可。
    return PopScope(
      canPop: _session == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_canvasEdit) {
          _setCanvasEdit(false); // 编辑先回使用，再按一次才退画布
          return;
        }
        _exitDetail();
      },
      child: Scaffold(
        // 键盘不压缩页面：输入框固定高度，键盘直接覆盖底部（与网页控制台一致）。
        // 配对页自行用 viewInsets 兜底（见 RtPairingView）。
        resizeToAvoidBottomInset: false,
        backgroundColor: pageBg,
        appBar: _session == null ? _buildLobbyAppBar(pageBg) : null,
        body: body,
      ),
    );
  }

  /// 大厅（连接列表）的标题栏：只有标题。
  ///
  /// 详情态（任何布局）不挂 AppBar——统一走页面级共享头部（返回 + 布局
  /// 胶囊），所有布局长得一样。
  PreferredSizeWidget _buildLobbyAppBar(Color pageBg) {
    return AppBar(
      title: const Text('远程输入'),
      backgroundColor: pageBg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
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
