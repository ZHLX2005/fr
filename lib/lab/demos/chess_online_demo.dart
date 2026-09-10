// lib/lab/demos/chess_online_demo.dart
// 国际象棋（Chess）互联网双人对战 — v3 Lua 状态机版
//
// 流程（v7 单入口）：
//   玩家输入昵称 + 房间号 → "进入对局"（tryJoinOrCreate：
//   房间存在 → join；404 → 用此号建房；先到者 = 房主）
//   → ChessRoomPage 准备阶段：房主配置执子色 / 残局 → 双方准备 → 开始
//
// 换肤：入口 AppBar 右侧"换肤"按钮 → 打开全屏换肤设置页
//   → 返回所选皮肤 id 写入 ChessSkinPrefs 持久化
//   → 建房/加入后把 skinId 传给 ChessRoomPage。
//
// 自定义棋盘颜色：设置页内"自定义棋盘颜色"区
//   → BoardColorPrefs 持久化；优先级：用户自定义 > 主题 context.chessColors。

import 'dart:async';

import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;
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
  BoardPalette? _boardPalette;

  /// 皮肤本地化器（一次创建，复用 http client + 目录 provider）。
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

  /// 下载失败的皮肤 id → 错误提示。
  String? _downloadErrorId;

  /// 下载失败的错误文案。
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    ChessSkinPrefs.read().then((id) {
      if (!mounted) return;
      setState(() => _skinId = id);
      _prefetchSkin(id);
    });
    BoardColorPrefs.read().then((palette) {
      if (!mounted) return;
      setState(() => _boardPalette = palette);
    });
  }

  Future<void> _prefetchSkin(String skinId) async {
    if (!ChessSkinLocalizer.isSupported) return;
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

  Future<void> _downloadSkin(String skinId) async {
    final meta = _metaById(skinId);
    if (meta == null) return;
    if (await _localizer.isCached(skinId)) {
      final cached = await _localizer.fromCache(skinId);
      if (cached != null && mounted) {
        setState(() {
          _localSkins[skinId] = cached;
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

  ChessSkinMeta? _metaById(String skinId) {
    for (final meta in ChessSkinBundle.metas) {
      if (meta.id == skinId) return meta;
    }
    return null;
  }

  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessRoomPage(
          handle: handle,
          skinId: _skinId,
          localSkin: _localSkins[_skinId],
          boardPalette: _boardPalette,
        ),
      ),
    );
    if (!mounted) return;
    _lobbyKey.currentState?.exposed.resetToEntry();
  }

  void _applyBoardPalette(BoardPalette? palette) {
    setState(() => _boardPalette = palette);
    if (palette == null) {
      BoardColorPrefs.clear();
    } else {
      BoardColorPrefs.write(palette);
    }
  }

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
    if (!_localSkins.containsKey(selected)) {
      await _prefetchSkin(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameLobbyPage(
      key: _lobbyKey,
      spec: kChessLobbySpec,
      slots: buildChessLobbySlots(
        actionsBuilder: (context) => [
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
