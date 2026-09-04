// lib/lab/demos/chess_online_demo.dart
// 国际象棋（Chess）互联网双人对战 — v3 Lua 状态机版
//
// 流程（社交房间号模式 social-room-code-pattern，与其它 Lua 游戏同构）：
//   玩家输入昵称 + 房间号 → "进入对局"（tryJoinOrCreate：
//   房间存在 → join；404 → 用此号建房；先到者 = 房主 = 白方）
//   → 等待房（房间号分享给朋友）→ 房主点"开始游戏" → state == "playing"
//   → onStarted 回调把 RoomHandle 交给 ChessRoomPage（业务层接管）
//
// 换肤：入口 AppBar 右侧"换肤"按钮 → 打开全屏换肤设置页（左列表 + 右棋盘预览）
//   → 返回所选皮肤 id 写入 ChessSkinPrefs（SharedPreferences）持久化
//   → 建房/加入后把 skinId 传给 ChessRoomPage，棋盘用所选皮肤。
//
// 自定义棋盘颜色：设置页内"自定义棋盘颜色"区（预设 + 拾色对话框）
//   → 点选即回调（onPaletteChanged）→ BoardColorPrefs（SharedPreferences）持久化
//   → 建房/加入后把 BoardPalette 传给 ChessRoomPage。
//   优先级：用户自定义 boardPalette > 主题 context.chessColors。
//
// 棋盘 / 皮肤 / 走法引擎全部复用 lib/core/chess/ 模块；
// 本 demo 只负责"入口 → 房间页"的路由与皮肤/配色状态。

import 'dart:async';

import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;
import '../../core/chess/endgame/chess_endgame.dart';
import '../../core/chess/endgame/chess_endgame_list_page.dart';
import '../../core/chess/lobby/chess_lobby_spec.dart';
import '../../core/chess/p2p/chess_room_page.dart';
import '../../core/chess/skins/chess_skin.dart';
import '../../core/chess/skins/chess_skin_localizer.dart';
import '../../core/chess/skins/chess_skin_meta.dart';
import '../../core/chess/skins/chess_skin_prefs.dart';
import '../../core/chess/skins/chess_skin_settings_page.dart';
import '../../core/chess/skins/file_resolver.dart';
import '../../core/chess/skins/local_chess_skin.dart';
import '../../core/chess/widgets/board_color_prefs.dart';
import '../../core/chess/widgets/board_palette.dart';
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class ChessOnlineDemo extends DemoPage {
  ChessOnlineDemo();
  @override
  String get title => '国际象棋（联机）';
  @override
  String get slug => 'chess-online';
  @override
  String get description => 'Chess 互联网双人对战 · v3 Lua 服务端权威';
  @override
  bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const ChessOnlinePage();
}

void registerChessOnlineDemo() => demoRegistry.register(ChessOnlineDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class ChessOnlinePage extends StatefulWidget {
  const ChessOnlinePage({super.key, this.localizer});

  /// 皮肤本地化器注入（测试用）。null → 生产默认构造（真实 path_provider + http）。
  final ChessSkinLocalizer? localizer;

  @override
  State<ChessOnlinePage> createState() => _ChessOnlinePageState();
}

class _ChessOnlinePageState extends State<ChessOnlinePage> {
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 当前选中的皮肤 id（默认 catalog 第一套 '1'；initState 从 SharedPreferences 加载）。
  String _skinId = kChessSkinsCatalog.first.id;

  /// 自定义棋盘配色（null = 跟随主题；initState 从 SharedPreferences 加载）。
  /// 优先级：用户自定义 > 主题 context.chessColors。
  BoardPalette? _boardPalette;

  /// 已选残局快照（null = 标准开局；残局列表页 pop 返回）。
  /// 传给 ChessLobbyPage（建房 initial_fen）+ ChessRoomPage（回放起点 / 标题）。
  ChessEndgameSnapshot? _selectedEndgame;

  /// 皮肤本地化器（一次创建，复用 http client + 目录 provider）。
  /// baseUrl 与 kDefaultChessSkinBaseUrl 一致（demo 的 relayUrl 同源）。
  ///
  /// `metaById` 指向 live [ChessSkinBundle.metas]（catalog + KV 合入）——
  /// 让 `isCached` / `fromCache` / `download` 用**同一份 meta** 判断，
  /// 避免 KV 覆盖同 id 后 localizer 仍按旧 const catalog 判缓存的错位（Fix）。
  late final ChessSkinLocalizer _localizer =
      widget.localizer ??
      ChessSkinLocalizer(
        resolver: const PublicFileResolver(baseUrl: kDefaultChessSkinBaseUrl),
        metaById: _metaById,
      );

  /// 已本地化的皮肤缓存（id → LocalChessSkin）。
  final Map<String, LocalChessSkin> _localSkins = {};

  /// 正在下载中的皮肤 id（null = 空闲）。
  String? _downloadingId;

  /// 下载失败的皮肤 id → 错误提示（null = 无错误；下载成功后清空）。
  String? _downloadErrorId;

  /// 下载失败的错误文案（展示在设置页预览区）。
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    // 加载持久化的换肤选择（无记录时 read() 回退 '1'）。
    ChessSkinPrefs.read().then((id) {
      if (!mounted) return;
      setState(() => _skinId = id);
      // 进入即预取：持久化皮肤已有本地缓存 → 直接加载；
      // 未缓存 → 后台下载（用户点"开始"前完成）。
      _prefetchSkin(id);
    });
    // 加载持久化的自定义棋盘配色（无记录 / 未启用 → null = 跟随主题）。
    BoardColorPrefs.read().then((palette) {
      if (!mounted) return;
      setState(() => _boardPalette = palette);
    });
  }

  /// 确保 [skinId] 已本地化：命中缓存直接加载；未命中 → 后台下载。
  ///
  /// 下载决策收敛到 [_downloadSkin]（它内部缓存优先 + 状态管理），
  /// 本方法只补一层"后台预取不转圈"的意图（web 直接跳过）。
  Future<void> _prefetchSkin(String skinId) async {
    if (!ChessSkinLocalizer.isSupported) return; // web 回退网络皮肤
    try {
      await _downloadSkin(skinId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadErrorId = skinId;
        _downloadError = '$e';
      });
    }
  }

  /// 确保 [skinId] 已本地化并写入 [_localSkins]（下载决策收敛到本方法）。
  ///
  /// 缓存优先（Fix）：磁盘已有完整缓存 → [ChessSkinLocalizer.ensureLocal]
  /// 立即返回 —— **不设 [_downloadingId]（不转圈）、不删缓存、不联网**。
  /// 仅未缓存 → 才进入下载态（转圈）+ 网络下载。
  ///
  /// 调用方（设置页点选 / 重试 / initState 预取）都走这里，单一权威路径。
  Future<void> _downloadSkin(String skinId) async {
    final meta = _metaById(skinId);
    if (meta == null) return;
    // 先探测是否已缓存：命中 → 直接加载，跳过 loading 态。
    if (await _localizer.isCached(skinId)) {
      final cached = await _localizer.fromCache(skinId);
      if (cached != null && mounted) {
        setState(() {
          _localSkins[skinId] = cached;
          // 清理该皮肤残留的 loading / 错误态（避免历史失败污染本次）。
          if (_downloadingId == skinId) _downloadingId = null;
          if (_downloadErrorId == skinId) _downloadErrorId = null;
          if (_downloadError != null && _downloadErrorId == skinId) {
            _downloadError = null;
          }
        });
      }
      return;
    }
    setState(() {
      _downloadingId = skinId;
      if (_downloadErrorId == skinId) _downloadErrorId = null;
    });
    try {
      final skin = await _localizer.download(meta);
      if (!mounted) return;
      setState(() {
        _localSkins[skinId] = skin;
        _downloadingId = null;
        _downloadErrorId = null;
        _downloadError = null;
      });
    } on TimeoutException {
      // 网络黑洞（不可达不拒绝）→ GET 挂起被超时掐断 → 明确文案 + 重试。
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _downloadErrorId = skinId;
        _downloadError = '下载超时，请检查网络后重试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _downloadErrorId = skinId;
        _downloadError = '下载失败，请检查网络后重试';
      });
    }
  }

  /// 从 live 注册表（catalog + KV 合入）按 id 找 [ChessSkinMeta]。
  ///
  /// 用 [ChessSkinBundle.metas] 而非 `kChessSkinsCatalog` —— 后者是 const
  /// 编译期快照，看不到 KV 合入的新皮肤（Fix：KV 皮肤同样可本地化）。
  ChessSkinMeta? _metaById(String skinId) {
    for (final meta in ChessSkinBundle.metas) {
      if (meta.id == skinId) return meta;
    }
    return null;
  }

  /// 大厅 state 推进时触发，把房间句柄交给对弈房间页。
  /// 传入当前选中的 [skinId] + 已本地化的 [localSkin]（若可用）+ 自定义棋盘配色，
  /// 对弈页优先用本地文件渲染 —— 零网络、离线可用。
  /// 对弈页 pop 回来后 → 大厅重置回入口表单（同一房间号可重开新局）。
  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessRoomPage(
          handle: handle,
          skinId: _skinId,
          localSkin: _localSkins[_skinId],
          boardPalette: _boardPalette,
          initialEndgame: _selectedEndgame,
        ),
      ),
    );
    if (!mounted) return;
    _lobbyKey.currentState?.exposed.resetToEntry();
  }

  /// 打开残局库：选快照 → 注入 LobbyPage 建房参数（initial_fen）；
  /// 取消（pop null）→ 保持原选择。
  Future<void> _openEndgameList() async {
    final snap = await Navigator.of(context).push<ChessEndgameSnapshot>(
      MaterialPageRoute(
        builder: (_) => ChessEndgameListPage(
          skin: _localSkins[_skinId],
        ),
      ),
    );
    if (!mounted || snap == null) return;
    setState(() => _selectedEndgame = snap);
  }

  /// 设置页内改动自定义棋盘配色时回调：实时应用 + 持久化。
  /// null = 清除自定义（跟随主题）。
  void _applyBoardPalette(BoardPalette? palette) {
    setState(() => _boardPalette = palette);
    // 持久化（fire-and-forget，失败不影响本次会话）。
    if (palette == null) {
      BoardColorPrefs.clear();
    } else {
      BoardColorPrefs.write(palette);
    }
  }

  /// 打开全屏换肤设置页：左侧皮肤列表 + 自定义棋盘颜色 + 右侧实时棋盘预览。
  /// 皮肤：返回时携带当前选中的皮肤 id → setState 切换 + 持久化 + 确保已本地化。
  /// 配色：点选即回调（onPaletteChanged）实时应用 + 持久化，不等返回。
  Future<void> _openSkinSettings() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChessSkinSettingsPage(
          initialSkinId: _skinId,
          initialPalette: _boardPalette,
          onPaletteChanged: _applyBoardPalette,
          localSkins: _localSkins,
          onRequestDownload: _downloadSkin,
          isDownloading: (id) => _downloadingId == id,
          downloadError: (id) => _downloadErrorId == id ? _downloadError : null,
          onRetryDownload: _downloadSkin,
        ),
      ),
    );
    if (selected == null || selected == _skinId) return;
    setState(() => _skinId = selected);
    await ChessSkinPrefs.write(selected);
    // 新选中的皮肤可能还没本地化 → 立即后台下载（settings 页选择时已触发过一次，
    // 这里兜底：直接从此入口选（换肤按钮）时也能预取）。
    if (!_localSkins.containsKey(selected)) {
      await _prefetchSkin(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 社交房间号入口（GameLobbyPage 自带 Scaffold + AppBar）：
    // 单表单（昵称 + 房间号）→ 等待房 → playing 后由 onStarted push
    // ChessRoomPage 接管界面；对弈页 pop 回来 → resetToEntry 回入口。
    return GameLobbyPage(
      key: _lobbyKey,
      spec: kChessLobbySpec,
      slots: buildChessLobbySlots(
        initialEndgame: _selectedEndgame,
        onClearEndgame: () => setState(() => _selectedEndgame = null),
        actionsBuilder: (context) => [
          // 残局库按钮：选残局快照 → 建房从该局面开始（先手方）。
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: '残局',
            onPressed: _openEndgameList,
          ),
          // 换肤设置按钮：打开全屏换肤设置页（所有阶段可见，无害）。
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: '换肤',
            onPressed: _openSkinSettings,
          ),
        ],
      ),
      onStarted: _onStarted,
    );
  }
}
