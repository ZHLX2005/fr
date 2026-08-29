// lib/lab/demos/chess_online_demo.dart
// 国际象棋（Chess）互联网双人对战 — v3 Lua 状态机版
//
// 流程（RelayV3Lobby 标准流程）：
//   玩家输入昵称 → 创建房间（host = 白方）或加入房间（guest = 黑方）
//   → lobby 等待 → 房主点"开始游戏" → state == "playing"
//   → onStarted 回调把 RoomHandle 交给 ChessRoomPage（业务层接管）
//
// 换肤：入口 AppBar 右侧"换肤"按钮 → 打开全屏换肤设置页（左列表 + 右棋盘预览）
//   → 返回所选皮肤 id 写入 ChessSkinPrefs（SharedPreferences）持久化
//   → 建房/加入后把 skinId 传给 ChessRoomPage，棋盘用所选皮肤。
//
// 棋盘 / 皮肤 / 走法引擎全部复用 lib/core/chess/ 模块；
// 本 demo 只负责"大厅 → 房间页"的入口路由。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/net_engine/relay_v3/relay_v3_widget.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;
import '../../core/chess/p2p/chess_script.dart';
import '../../core/chess/p2p/chess_room_page.dart';
import '../../core/chess/skins/chess_skin.dart';
import '../../core/chess/skins/chess_skin_localizer.dart';
import '../../core/chess/skins/chess_skin_meta.dart';
import '../../core/chess/skins/chess_skin_prefs.dart';
import '../../core/chess/skins/chess_skin_settings_page.dart';
import '../../core/chess/skins/file_resolver.dart';
import '../../core/chess/skins/local_chess_skin.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class ChessOnlineDemo extends DemoPage {
  ChessOnlineDemo();
  @override
  String get title => '国际象棋在线';
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
  const ChessOnlinePage({super.key});
  @override
  State<ChessOnlinePage> createState() => _ChessOnlinePageState();
}

class _ChessOnlinePageState extends State<ChessOnlinePage> {
  /// 当前选中的皮肤 id（默认 catalog 第一套 '1'；initState 从 SharedPreferences 加载）。
  String _skinId = kChessSkinsCatalog.first.id;

  /// 皮肤本地化器（一次创建，复用 http client + 目录 provider）。
  /// baseUrl 与 kDefaultChessSkinBaseUrl 一致（demo 的 relayUrl 同源）。
  late final ChessSkinLocalizer _localizer = ChessSkinLocalizer(
    resolver: const PublicFileResolver(baseUrl: kDefaultChessSkinBaseUrl),
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
  }

  /// 确保 [skinId] 已本地化：命中缓存直接加载；未命中 → 后台下载。
  ///
  /// 下载成功写入 [_localSkins]；失败记 [_downloadErrorId]/[_downloadError]
  /// （不崩溃，UI 可重试）。
  Future<void> _prefetchSkin(String skinId) async {
    if (!ChessSkinLocalizer.isSupported) return; // web 回退网络皮肤
    try {
      if (await _localizer.isCached(skinId)) {
        final cached = await _localizer.fromCache(skinId);
        if (cached != null) {
          if (!mounted) return;
          setState(() => _localSkins[skinId] = cached);
          return;
        }
      }
      await _downloadSkin(skinId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadErrorId = skinId;
        _downloadError = '$e';
      });
    }
  }

  /// 下载 [skinId] 的皮肤资源到本地并写入 [_localSkins]。
  Future<void> _downloadSkin(String skinId) async {
    final meta = _metaById(skinId);
    if (meta == null) return;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _downloadErrorId = skinId;
        _downloadError = '下载失败，请检查网络后重试';
      });
    }
  }

  /// 从 const catalog 按 id 找 [ChessSkinMeta]。
  ChessSkinMeta? _metaById(String skinId) {
    for (final meta in kChessSkinsCatalog) {
      if (meta.id == skinId) return meta;
    }
    return null;
  }

  /// Relay v3 大厅 → state=="playing" 时触发，把房间句柄交给对弈房间页。
  /// 传入当前选中的 [skinId] + 已本地化的 [localSkin]（若可用），
  /// 对弈页优先用本地文件渲染 —— 零网络、离线可用。
  void _onStarted(RoomHandle handle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessRoomPage(
          handle: handle,
          skinId: _skinId,
          localSkin: _localSkins[_skinId],
        ),
      ),
    );
  }

  /// 打开全屏换肤设置页：左侧皮肤列表 + 右侧实时棋盘预览。
  /// 返回时携带当前选中的皮肤 id → setState 切换 + 持久化 + 确保已本地化。
  Future<void> _openSkinSettings() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChessSkinSettingsPage(
          initialSkinId: _skinId,
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
    // RelayV3Lobby 自带 Scaffold + AppBar（建房 / 加入 / 大厅 / 开始）。
    // 进入 playing 后 lobby 内部渲染 SizedBox.shrink（见 RelayV3Lobby.build），
    // 由 onStarted push 的 ChessRoomPage 接管界面。
    return RelayV3Lobby(
      relayUrl: 'http://47.110.80.47:8988',
      script: kChessScript,
      maxPlayers: 2,
      title: '国际象棋在线',
      onStarted: _onStarted,
      actionsBuilder: (context) => [
        // 换肤设置按钮：打开全屏换肤设置页（所有阶段可见，无害）。
        IconButton(
          icon: const Icon(Icons.palette_outlined),
          tooltip: '换肤',
          onPressed: _openSkinSettings,
        ),
      ],
    );
  }
}
