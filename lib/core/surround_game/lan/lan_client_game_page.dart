// lib/core/surround_game/lan/lan_client_game_page.dart
//
// LAN 客户端游戏页面 — 单面板布局。
//
// 布局：
// ┌────────────────────────────────────────┐
// │ ← 退出   房间名     [● 在线]           │  AppBar
// ├────────────────────────────────────────┤
// │                                        │
// │            棋盘（flipY=false）          │  通过 LanBoardStack
// │                                        │
// ├────────────────────────────────────────┤
// │      自己的 PlayerPanel (isTop=false)   │  底部
// └────────────────────────────────────────┘

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import '../board_theme.dart';
import '../surround_game_constants.dart';
import '../widgets/player_panel.dart';
import '../widgets/touch_controller.dart';
import '../engine/game_engine.dart';
import '../models/game_state.dart';
import 'widgets/lan_board_stack.dart';
import 'widgets/touch_controller_factory.dart';
import 'protocol/lan_channels.dart';
import 'service/lan_service_adapter.dart';
import 'victory_overlay.dart';

/// LAN 客户端游戏页面
///
/// 单面板布局：棋盘居中（不翻转），底部仅显示 client 自己的 PlayerPanel。
/// touchController 使用普通 [TouchController]（不镜像 y 坐标）。
/// isMyTurn = !gs.currentPlayerIsTop（client 是 bottom player）。
///
/// 状态同步：通过 LanServiceAdapter.createGameSession 建立双端 Session，
/// 走固定 channel 'surround/game/state'。任一端修改 ValueNotifier 都会自动
/// serialize + 推送给对端；对端收到后用 serializer 在原 notifier 上反序列化，
/// 触发 onChanged 回调刷新 UI。
///
/// Client 不主动 syncFull（等 Host 推初始 state）。
class LanClientGamePage extends StatefulWidget {
  final String roomId;
  final String hostDeviceId;

  const LanClientGamePage({super.key, required this.roomId, required this.hostDeviceId});

  @override
  State<LanClientGamePage> createState() => _LanClientGamePageState();
}

class _LanClientGamePageState extends State<LanClientGamePage> {
  TouchController _touchController = TouchController();
  ValueNotifier<GameState>? _gameStateNotifier;
  Session<ValueNotifier<GameState>>? _session;
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<LanServiceError>? _errorSub;

  @override
  void initState() {
    super.initState();
    _gameStateNotifier = ValueNotifier<GameState>(QuoridorEngine.initialize());
    _session = LanServiceAdapter.instance.createGameSession(
      peerDeviceId: widget.hostDeviceId,
      state: _gameStateNotifier!,
      channelName: LanChannels.gameState,
    );
    _session!.onChanged = () {
      if (mounted) setState(() {});
    };
    // Client 不调 syncFull — 等 Host 推初始 state
    // deviceLost 检测
    _devicesSub = LanServiceAdapter.instance.watchDevices().listen(_onDevices);
    // 错误 SnackBar
    _errorSub = LanServiceAdapter.instance.watchErrors().listen(_onError);
  }

  void _onDevices(List<Device> devices) {
    if (!devices.any((d) => d.deviceId == widget.hostDeviceId)) {
      _showDisconnectDialog();
    }
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  void _showDisconnectDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('对手已掉线'),
        content: const Text('连接已断开，请返回房间列表。'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _errorSub?.cancel();
    _session?.dispose();
    _gameStateNotifier?.dispose();
    _touchController.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: ValueListenableBuilder<GameState>(
          valueListenable: _gameStateNotifier!,
          builder: (_, gs, _) => Stack(
            children: [
              _buildBody(gs, theme),
              if (gs.status != GameStatus.running)
                VictoryOverlay(
                  theme: theme,
                  status: gs.status,
                  onRestart: () {}, // Client 端无再来一局触发逻辑
                  onExit: _onExit,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(GameState gs, BoardThemeData theme) {
    final isMyTurn = !gs.currentPlayerIsTop; // client 是 bottom player
    final isRunning = gs.status == GameStatus.running;
    return _buildGameScreen(gs, theme, isRunning: isRunning, isMyTurn: isMyTurn);
  }

  PreferredSizeWidget _buildAppBar(BoardThemeData theme) {
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.btnText),
        onPressed: () => _showExitConfirm(context, theme),
      ),
      title: Text(
        '房间 ${widget.roomId}',
        style: TextStyle(color: theme.btnText, fontSize: 14),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '在线',
                style: TextStyle(color: theme.btnSub, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      backgroundColor: theme.boardSurface,
      elevation: 0,
    );
  }

  Widget _buildGameScreen(
    GameState gs,
    BoardThemeData theme, {
    Widget? overlay,
    required bool isRunning,
    required bool isMyTurn,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cellSize = w / 11;
        final boardSize = w; // = cellSize * 11

        // 首次或 boardSize 变化时升级 touchController（client 用普通 TouchController）
        _ensureClientTouchController(boardSize);

        return Stack(
          children: [
            Column(
              children: [
                // 棋盘
                Expanded(
                  child: Center(
                    child: LanBoardStack(
                      gameState: gs,
                      touchController: _touchController,
                      theme: theme,
                      cellSize: cellSize,
                      flipY: false, // client 不翻转
                      isMyTurn: isMyTurn,
                      onChanged: () => setState(() {}),
                      onConfirm: _onConfirm(gs),
                      onCancel: _onCancel,
                      validateWall: _validateWall,
                    ),
                  ),
                ),
                // 底部操作行
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Center(
                    child: _buildPlayerPanel(
                      gs: gs,
                      theme: theme,
                      isTop: false, // client 是 bottom
                      isTopTurn: gs.currentPlayerIsTop,
                      isRunning: isRunning,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    top: 6,
                    bottom: 6,
                    right: 16,
                  ),
                  child: Row(
                    children: [
                      _bottomAction(
                        icon: Icons.exit_to_app,
                        label: '退出',
                        theme: theme,
                        onTap: () => _showExitConfirm(context, theme),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ?overlay,
          ],
        );
      },
    );
  }

  // ═══════════════════ TouchController 生命周期 ═══════════════════

  void _ensureClientTouchController(double boardSize) {
    // Client 用普通 TouchController — 不镜像 y 坐标。
    // 这里仅在尺寸变化时 reset，避免布局变化导致旧 pending 状态残留。
    if (_touchController is LanHostTouchController) {
      _touchController = TouchController();
    }
  }

  // ═══════════════════ PlayerPanel ═══════════════════

  Widget _buildPlayerPanel({
    required GameState gs,
    required BoardThemeData theme,
    required bool isTop,
    required bool isTopTurn,
    required bool isRunning,
  }) {
    final toc = _touchController;
    final isCurrentTurn = isTop == gs.currentPlayerIsTop;
    final active = isRunning && isCurrentTurn;

    final playerSteps = gs.history
        .where((m) => !m.isWall && m.isTopPlayer == isTop)
        .length;
    final wallsPlaced =
        isTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final remainingWalls =
        SurroundGameConstants.wallCountPerPlayer - wallsPlaced;

    return PlayerPanel(
      rotated: false, // 底部面板不旋转
      active: active,
      isTop: isTop,
      mode: toc.mode,
      phase: toc.phase,
      canPlaceWall: remainingWalls > 0,
      playerSteps: playerSteps,
      remainingWalls: remainingWalls,
      canRequestUndo: false,
      onToggleMode: active ? () => _toggleMode() : null,
      onUndoRequest: null,
      onConfirm: (toc.phase == TouchPhase.confirming && active)
          ? _onConfirm(gs)
          : null,
      onCancel: (toc.phase == TouchPhase.confirming && active)
          ? _onCancel
          : null,
      onRotate: (toc.phase == TouchPhase.confirming && active)
          ? _onRotate(gs)
          : null,
      pendingWall: toc.pendingWall,
    );
  }

  // ═══════════════════ Touch event forwarding ═══════════════════

  // 注意：触摸 PDS 事件由 LanBoardStack 内部转发到 touchController。
  // Page 级的 _onPointerDown 等不再需要（已迁移到 LanBoardStack）。
  // 仅保留 confirm/cancel/rotate 操作（供 PlayerPanel 按钮和 LanBoardStack 内部使用）。

  bool _validateWall(
    GameState gs, int wx, int wy, WallOrientation o,
  ) {
    return QuoridorEngine.isWallPlacementValid(
      gs.wallGrid, gs.adjacency,
      gs.topPlayerId, gs.bottomPlayerId,
      wx, wy, o,
    );
  }

  VoidCallback _onConfirm(GameState gs) {
    return () {
      final toc = _touchController;
      if (toc.phase != TouchPhase.confirming) return;

      final current = _gameStateNotifier!.value;
      GameState? result;
      if (toc.pendingWall != null) {
        final pw = toc.pendingWall!;
        result = QuoridorEngine.placeWall(current, pw.x, pw.y, pw.o);
      } else {
        result = QuoridorEngine.movePiece(current, toc.pendingTargetCellId ?? 0);
      }
      if (result == null) {
        toc.reset();
        setState(() {});
        return;
      }
      final next = QuoridorEngine.switchTurn(result);
      _gameStateNotifier!.value = next; // Session 自动 serialize + 发
      toc.reset();
      setState(() {});
    };
  }

  VoidCallback get _onCancel {
    return () {
      _touchController.cancelAction();
      setState(() {});
    };
  }

  void _onExit() {
    Navigator.of(context).pop();
  }

  VoidCallback _onRotate(GameState gs) {
    return () {
      _touchController.rotatePendingWall(
        validateWall: (wx, wy, o) => _validateWall(gs, wx, wy, o),
      );
      setState(() {});
    };
  }

  void _toggleMode() {
    _touchController.toggleMode();
    setState(() {});
  }

  // ═══════════════════ Dialogs ═══════════════════

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required BoardThemeData theme,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final color = theme.btnText.withValues(alpha: enabled ? 0.5 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  void _showExitConfirm(BuildContext context, BoardThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(Icons.exit_to_app,
                size: 32, color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text('退出游戏',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: theme.btnText)),
            const SizedBox(height: 4),
            Text('当前对局记录将丢失',
                style: TextStyle(fontSize: 13, color: theme.btnSub)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      side: BorderSide(color: theme.btnBorder),
                    ),
                    child: Text('取消',
                        style: TextStyle(color: theme.btnText)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _touchController.reset();
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: theme.piecePlayerA,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('确定',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
