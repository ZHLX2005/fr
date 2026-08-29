// lib/lab/demos/chess_online_demo.dart
// 国际象棋（Chess）互联网双人对战 — v3 Lua 状态机版
//
// 流程（RelayV3Lobby 标准流程）：
//   玩家输入昵称 → 创建房间（host = 白方）或加入房间（guest = 黑方）
//   → lobby 等待 → 房主点"开始游戏" → state == "playing"
//   → onStarted 回调把 RoomHandle 交给 ChessRoomPage（业务层接管）
//
// 换肤：入口 AppBar 右侧"换肤"按钮 → 弹皮肤选择对话框（7 套 catalog）
//   → 选择写入 ChessSkinPrefs（SharedPreferences）持久化
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
import '../../core/chess/skins/chess_skin_meta.dart';
import '../../core/chess/skins/chess_skin_prefs.dart';
import '../../widgets/context_chess_colors.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class ChessOnlineDemo extends DemoPage {
  ChessOnlineDemo();
  @override String get title => '国际象棋在线';
  @override String get slug => 'chess-online';
  @override String get description => 'Chess 互联网双人对战 · v3 Lua 服务端权威';
  @override bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const ChessOnlinePage();
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

  @override
  void initState() {
    super.initState();
    // 加载持久化的换肤选择（无记录时 read() 回退 '1'）。
    ChessSkinPrefs.read().then((id) {
      if (!mounted) return;
      setState(() => _skinId = id);
    });
  }

  /// Relay v3 大厅 → state=="playing" 时触发，把房间句柄交给对弈房间页。
  /// 传入当前选中的 [skinId]，棋盘用所选皮肤渲染。
  void _onStarted(RoomHandle handle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessRoomPage(handle: handle, skinId: _skinId),
      ),
    );
  }

  /// 打开换肤选择对话框：列出 7 套皮肤（棋子缩略图 + 显示名 + 选中勾）。
  /// 点选 → setState 切换 + 持久化 + 关闭对话框。
  Future<void> _showSkinPicker() async {
    final colors = context.chessColors;
    final theme = Theme.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: const Text('选择棋盘皮肤'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: kChessSkinsCatalog.length,
              separatorBuilder: (_, _) => Divider(
                height: 1, color: colors.gridLine.withValues(alpha: 0.3),
              ),
              itemBuilder: (context, i) {
                final meta = kChessSkinsCatalog[i];
                // 用当前注册表解析皮肤（拿到 pieces 里的 wK 缩略图）。
                final skin = ChessSkinBundle.byId(meta.id);
                final isSelected = meta.id == _skinId;
                return ListTile(
                  leading: _SkinThumb(skin: skin),
                  title: Text(meta.displayName),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: colors.checkWarning)
                      : null,
                  selected: isSelected,
                  selectedTileColor: colors.lightSquare.withValues(alpha: 0.35),
                  onTap: () => Navigator.of(dialogContext).pop(meta.id),
                );
              },
            ),
          ),
        );
      },
    );
    if (selected == null || selected == _skinId) return;
    setState(() => _skinId = selected);
    await ChessSkinPrefs.write(selected);
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
        // 换肤设置按钮：弹皮肤选择对话框（所有阶段可见，无害）。
        IconButton(
          icon: const Icon(Icons.palette_outlined),
          tooltip: '换肤',
          onPressed: _showSkinPicker,
        ),
      ],
    );
  }
}

/// 皮肤棋子缩略图（wK 王棋图像；无图像时回退 unicode ♔）。
class _SkinThumb extends StatelessWidget {
  final ChessSkin skin;

  const _SkinThumb({required this.skin});

  @override
  Widget build(BuildContext context) {
    final image = skin.pieces['wK'];
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      child: image != null
          ? Image(image: image, width: 32, height: 32, fit: BoxFit.contain)
          : const Text('♔',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
    );
  }
}
