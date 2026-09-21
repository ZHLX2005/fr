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
// v10 皮肤线上化（id49）：
//   1. 启动期不再注册 7 套硬编码皮肤；皮肤清单全部来自线上 KV index。
//   2. 进入本页（initState）→ _initSkins：磁盘持久化 index 离线恢复；
//      首启无缓存强拉 KV index（失败页面横幅提示重试）。
//   3. 进房门禁：点"进入对局"后若皮肤尚未就绪，弹遮罩等待下载完成；
//      失败则提示"皮肤资源未下载完成"并留在大厅，不放行进房。
//
// 自定义棋盘颜色：设置页内"自定义棋盘颜色"区
//   → BoardColorPrefs 持久化；优先级：用户自定义 > 主题 context.chessColors。

import 'dart:async';

import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;
import '../../core/chess/replay/chess_game_record_list_page.dart';
import '../../core/chess/lobby/chess_lobby_spec.dart';
import '../../core/chess/p2p/chess_room_page.dart';
import '../../core/chess/skins/chess_skin.dart';
import '../../core/chess/skins/chess_skin_localizer.dart';
import '../../core/chess/skins/chess_skin_meta.dart';
import '../../core/chess/skins/chess_skin_meta_sync.dart' show fetchAndMergeSkins;
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
  const ChessOnlinePage({
    super.key,
    this.localizer,
    this.onFetchKvIndex,
  });

  /// 皮肤本地化器注入（测试用）。null → 生产默认构造（真实 path_provider + http）。
  final ChessSkinLocalizer? localizer;

  /// KV index 强拉注入点（测试用）。null → 生产 `fetchAndMergeSkins()`。
  final Future<bool> Function()? onFetchKvIndex;

  @override
  State<ChessOnlinePage> createState() => _ChessOnlinePageState();
}

class _ChessOnlinePageState extends State<ChessOnlinePage> {
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 当前选中的皮肤 id（initState 从磁盘恢复 / 强拉后确定）。
  String _skinId = kDefaultChessSkinId;

  /// 皮肤初始化失败（首启无缓存且 KV 强拉失败）→ 页面顶部横幅 + 重试，
  /// 进房门禁（_onStarted）同样不放行。
  bool _skinInitError = false;

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

  /// 去重：进行中的下载（skinId → future），防止入口预取与进房门禁并发重复下载。
  final Map<String, Future<void>> _inflightDownloads = {};

  @override
  void initState() {
    super.initState();
    _initSkins();
    BoardColorPrefs.read().then((palette) {
      if (!mounted) return;
      setState(() => _boardPalette = palette);
    });
  }

  /// v10 皮肤初始化（皮肤线上化 id49：启动期 registerHardcoded 已删除）：
  ///   1. 磁盘有持久化 KV index → 离线恢复注册表（零网络）。
  ///   2. 无缓存（首装 / 清数据）→ **强拉** KV index；失败置错误态
  ///      （页面横幅提示重试；进房门禁同样不放行 —— 首启必须拉到皮肤）。
  ///   3. 读 prefs 选中皮肤；持久化 id 在线上清单失效（皮肤下架等）
  ///      → 回退线上第一套。
  ///   4. 预取下载选中皮肤（走现有 localizer 本地缓存）。
  Future<void> _initSkins() async {
    if (ChessSkinBundle.metas.isEmpty) {
      final restored = await ChessSkinBundle.restorePersistedIndex();
      if (!mounted) return;
      if (!restored && ChessSkinBundle.metas.isEmpty) {
        final fetch = widget.onFetchKvIndex ?? fetchAndMergeSkins;
        final ok = await fetch().catchError((Object _) => false);
        if (!mounted) return;
        if (!ok) {
          setState(() => _skinInitError = true);
          return;
        }
      }
    }
    var id = await ChessSkinPrefs.read();
    if (!mounted) return;
    if (_metaById(id) == null) {
      final metas = ChessSkinBundle.metas;
      if (metas.isEmpty) {
        // 注册表仍空（restore/fetch 均未成功）→ 提示重试。
        setState(() => _skinInitError = true);
        return;
      }
      id = metas.first.id;
    }
    setState(() => _skinId = id);
    _prefetchSkin(id);
  }

  /// 首启强拉失败后的重试入口（横幅按钮）。
  Future<void> _retrySkinInit() async {
    if (!mounted) return;
    setState(() => _skinInitError = false);
    await _initSkins();
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

  /// 皮肤下载入口（幂等 + 去重）。设置页与进房门禁共用。
  Future<void> _downloadSkin(String skinId) {
    final existing = _inflightDownloads[skinId];
    if (existing != null) return existing;
    final fut = _doDownloadSkin(skinId)
        .whenComplete(() => _inflightDownloads.remove(skinId));
    _inflightDownloads[skinId] = fut;
    return fut;
  }

  Future<void> _doDownloadSkin(String skinId) async {
    var meta = _metaById(skinId);
    if (meta == null) {
      // v8/v10：注册表未合入线上 KV index（首启强拉失败后重试下载、或
      // 持久化的皮肤 id 已下架）时 meta 解析 miss → 静默不下载 → 对局页
      // byId 回退 GameDefaultSkin → 全部棋子走 unicode 线条兜底。
      // 先 best-effort 合入 KV index（5s 超时），再重试一次 meta 解析。
      final merged = await fetchAndMergeSkins().catchError((Object _) => false);
      if (merged) meta = _metaById(skinId);
    }
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
    // v9：进房门禁 —— 入口页 initState 已开始预取，若用户在下载完成前点了
    // "进入对局"，这里阻塞等待皮肤就绪（弹进度遮罩）；失败则提示
    // "皮肤资源未下载完成"并留在大厅，不放行进房（避免对局内回退默认棋子）。
    if (ChessSkinLocalizer.isSupported && !_localSkins.containsKey(_skinId)) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SkinPreparingDialog(
          prepare: () async {
            await _downloadSkin(_skinId);
            return _localSkins.containsKey(_skinId);
          },
        ),
      );
      if (!mounted) return;
      if (ok != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('皮肤资源未下载完成，无法进入对局，请检查网络后重试'),
          ),
        );
        return;
      }
    }
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

  /// 对局回放库一级入口（id61：回放与皮肤平行，独立于房间流程）。
  /// 皮肤跟随当前选中：已本地化用本地缓存，否则按 id 解析（远程/unicode 兜底）。
  Future<void> _openReplayLibrary() async {
    final skin = _localSkins[_skinId] ?? ChessSkinBundle.byId(_skinId);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChessGameRecordListPage(skin: skin),
      ),
    );
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
    return Column(
      children: [
        // 首启强拉失败横幅（皮肤线上化 id49）：提示联网重试。
        if (_skinInitError)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: ListTile(
                leading: Icon(
                  Icons.cloud_off,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                title: Text(
                  '皮肤资源初始化失败（首次使用需联网下载）',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                ),
                trailing: TextButton.icon(
                  onPressed: _retrySkinInit,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                ),
              ),
            ),
          ),
        Expanded(
          child: GameLobbyPage(
            key: _lobbyKey,
            spec: kChessLobbySpec,
            slots: buildChessLobbySlots(
              actionsBuilder: (context) => [
                // 对局回放（id61：一级入口，与换肤平级；独立于开房间流程）。
                IconButton(
                  icon: const Icon(Icons.movie_outlined),
                  tooltip: '对局回放',
                  onPressed: _openReplayLibrary,
                ),
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: '换肤',
                  onPressed: _openSkinSettings,
                ),
              ],
            ),
            onStarted: _onStarted,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 皮肤准备遮罩（进房门禁）
// ══════════════════════════════════════════════════════════════

/// 进房前的皮肤准备进度遮罩：prepare 完成后自动关闭。
/// pop(true) = 皮肤已就绪；pop(false) = 下载失败。
class _SkinPreparingDialog extends StatefulWidget {
  const _SkinPreparingDialog({required this.prepare});

  final Future<bool> Function() prepare;

  @override
  State<_SkinPreparingDialog> createState() => _SkinPreparingDialogState();
}

class _SkinPreparingDialogState extends State<_SkinPreparingDialog> {
  @override
  void initState() {
    super.initState();
    widget.prepare().then((ok) {
      if (mounted) Navigator.of(context).pop(ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('皮肤资源准备中，请稍候…'),
          ],
        ),
      ),
    );
  }
}
