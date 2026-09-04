// lib/lab/demos/gomoku_lua_demo.dart
// 五子棋（Gomoku）互联网双人对战 — v3 Lua 状态机版（无房主版本）
//
// 流程：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → 服务端 join 尝试：404 → 用此号创建新房间
//   → 双方均进入后 ACK × 2 → 自动进入 playing
//
// 与围追堵截的差异：
//   - 15x15 对称棋盘，落子在交点
//   - 无镜像翻转（对称棋盘）
//   - 无房主区分：先进入=黑方（先手），后进入=白方
//   - 房间号由玩家口口相传，撞号时给提示换号
//   - 胜负 = 连五，客户端本地判定后发 WIN
//
// 入口迁移：原 LobbyEntryPage（lib/lab/demos/gomoku_lua/widgets.dart）
//   → GameLobbyPage + kGomokuLobbySpec（lib/core/gomoku/lobby/gomoku_lobby_spec.dart）。
//   「开局学习」入口移到 AppBar actionsBuilder（与 chess 残局库一致位置）。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'gomoku_lua/engine.dart' show RoomHandle;
import 'gomoku_lua/widgets.dart' show OnlineGamePage;
import 'gomoku_lua/opening/gomoku_opening_player.dart';
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/gomoku/skins/gomoku_skin.dart' show GomokuSkinBundle;
import '../../core/gomoku/skins/gomoku_skin_localizer.dart' show GomokuSkinLocalizer;
import '../../core/gomoku/skins/gomoku_skin_meta_sync.dart' show fetchAndMergeGomokuSkins;
import '../../core/gomoku/skins/gomoku_skin_prefs.dart' show GomokuSkinPrefs;
import '../../core/gomoku/skins/local_gomoku_skin.dart' show LocalGomokuSkin;
import '../../core/chess/skins/file_resolver.dart' show PublicFileResolver;
import '../../core/gomoku/lobby/gomoku_lobby_spec.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class GomokuLuaDemo extends DemoPage {
  GomokuLuaDemo();
  @override String get title => '五子棋（联机）';
  @override String get slug => 'gomoku-lua';
  @override String get description => 'Gomoku 互联网双人对战 · Lua 服务端权威棋谱';
  @override bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const GomokuLuaPage();
}

void registerGomokuLuaDemo() => demoRegistry.register(GomokuLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class GomokuLuaPage extends StatefulWidget {
  const GomokuLuaPage({super.key});
  @override
  State<GomokuLuaPage> createState() => _GomokuLuaPageState();
}

class _GomokuLuaPageState extends State<GomokuLuaPage> {
  String _skinId = "default";
  LocalGomokuSkin? _localSkin;
  bool _skinLoading = false;
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 「开局学习」开关（true → 替换为 GomokuOpeningPlayer 全屏页面）。
  bool _showOpeningStudy = false;

  /// 对弈页 → 大厅重置句柄（push 前快照，pop 后用 resetToEntry 回到表单）。
  RoomHandle? _activeHandle;

  @override
  void initState() {
    super.initState();
    _loadSkinPrefs();
    // 进入大厅即后台合入 KV 索引（best-effort，失败回退空 catalog）
    fetchAndMergeGomokuSkins();
  }

  Future<void> _loadSkinPrefs() async {
    final id = await GomokuSkinPrefs.read();
    if (!mounted) return;
    setState(() => _skinId = id);
    _ensureLocalFor(id);
  }

  Future<void> _ensureLocalFor(String id) async {
    if (id == "default") {
      if (_localSkin != null && mounted) setState(() => _localSkin = null);
      return;
    }
    // 已缓存 → 直接 fromCache（零网络，带 fileId 校验）
    final localizer = GomokuSkinLocalizer(
      resolver: const PublicFileResolver(baseUrl: "http://47.110.80.47:8988"),
    );
    if (await localizer.isCached(id)) {
      final cached = await localizer.fromCache(id);
      if (!mounted) return;
      if (cached != null) setState(() => _localSkin = cached);
      return;
    }
    // 未缓存：若 KV 已注册该 id，触发一次下载（best-effort）
    final meta = GomokuSkinBundle.metas.where((m) => m.id == id).toList();
    if (meta.isEmpty) return;
    if (_skinLoading) return;
    setState(() => _skinLoading = true);
    try {
      final skin = await localizer.ensureLocal(meta.first);
      if (!mounted) return;
      setState(() => _localSkin = skin);
    } catch (_) {
      // 网络失败 → 保持彩色回退，不抛
    } finally {
      if (mounted) setState(() => _skinLoading = false);
    }
  }


  /// 进入对局：push OnlineGamePage（带皮肤）；pop 后 resetToEntry。
  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    _activeHandle = handle;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineGamePage(
          handle: handle,
          onLeave: () async {
            await handle.leave();
          },
          skinId: _skinId,
          skin: _localSkin,
        ),
      ),
    );
    _activeHandle = null;
    if (!mounted) return;
    _lobbyKey.currentState?.exposed.resetToEntry();
  }

  @override
  void dispose() {
    _activeHandle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 「开局学习」全屏页（与入口互斥，与原版一致）。
    if (_showOpeningStudy) {
      return GomokuOpeningPlayer(
        onBack: () => setState(() => _showOpeningStudy = false),
      );
    }
    // 通用入口页（自带 Scaffold + AppBar + 表单）。
    // AppBar 加「开局学习」按钮（与原版卡片外的 TextButton 同语义）。
    return GameLobbyPage(
      key: _lobbyKey,
      spec: kGomokuLobbySpec,
      slots: GameLobbySlots(
        actionsBuilder: (context) => [
          // 皮肤指示（TODO: 抽 GameSkinSettingsPage 后替换为入口按钮）
          if (_skinId != "default")
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(_skinId, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: _skinLoading ? "皮肤加载中…" : "换肤（TODO：接入 GameSkinSettingsPage）",
            onPressed: _skinLoading
                ? null
                : () async {
                    // 轻量占位：循环切换 default ↔ 已注册皮肤，演示 wiring 已通
                    final metas = GomokuSkinBundle.metas;
                    if (metas.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("暂无可用皮肤（catalog 为空，KV 未发布）")),
                      );
                      return;
                    }
                    final ids = ["default", ...metas.map((m) => m.id)];
                    final idx = ids.indexOf(_skinId);
                    final next = ids[(idx + 1) % ids.length];
                    setState(() {
                      _skinId = next;
                      if (next == "default") _localSkin = null;
                    });
                    await GomokuSkinPrefs.write(next);
                    await _ensureLocalFor(next);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      // ignore: prefer_interpolation_to_compose_strings
                      SnackBar(content: Text(next == "default" ? "已切回默认（彩色圆）" : "已选用皮肤：$next" + (_localSkin != null ? "（本地）" : "（网络）") )),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.school_outlined),
            tooltip: '开局学习',
            onPressed: () => setState(() => _showOpeningStudy = true),
          ),
        ],
      ),
      onStarted: _onStarted,
    );
  }
}