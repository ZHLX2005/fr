// lib/core/surround_game/lan/lan_host_game_page.dart
//
// LAN 主机游戏页面 — 单面板布局。
//
// 布局：
// ┌────────────────────────────────────────┐
// │ ← 退出   房间名     [● 在线]           │  AppBar
// ├────────────────────────────────────────┤
// │                                        │
// │            棋盘（flipY=true）           │  通过 LanBoardStack
// │                                        │
// ├────────────────────────────────────────┤
// │        自己的 PlayerPanel (isTop)       │  底部
// └────────────────────────────────────────┘

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_channels.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/service/lan_service_adapter.dart';
import '../board_theme.dart';
import '../surround_game_constants.dart';
import '../widgets/player_panel.dart';
import '../widgets/touch_controller.dart';
import '../engine/game_engine.dart';
import '../models/game_state.dart';
import 'widgets/lan_board_stack.dart';
import 'widgets/touch_controller_factory.dart';
import 'victory_overlay.dart';

/// LAN 主机游戏页面
///
/// 单面板布局：棋盘居中（flipY=true 翻转，host 是 top player 视觉在下方），
/// 底部仅显示 host 自己的 PlayerPanel。
/// touchController 使用 [LanHostTouchControllerFactory] 创建，带 y 坐标镜像。
///
/// 状态同步：通过 LanServiceAdapter.createGameSession 建立双端 Session，
/// 走固定 channel 'surround/game/state'。任一端修改 ValueNotifier 都会自动
/// serialize + 推送给对端；对端收到后用 serializer 在原 notifier 上反序列化，
/// 触发 onChanged 回调刷新 UI。
class LanHostGamePage extends StatefulWidget {
  final String roomId;
  final String peerDeviceId;

  const LanHostGamePage({super.key, required this.roomId, required this.peerDeviceId});

  @override
  State<LanHostGamePage> createState() => _LanHostGamePageState();
}

class _LanHostGamePageState extends State<LanHostGamePage> {
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
      peerDeviceId: widget.peerDeviceId,
      state: _gameStateNotifier!,
      channelName: LanChannels.gameState,
    );
    _session!.onChanged = () {
      if (mounted) setState(() {});
    };
    // Host 主动发初始 state（让 Client 进入后立刻收到）
    _session!.syncFull();
    // deviceLost 检测
    _devicesSub = LanServiceAdapter.instance.watchDevices().listen(_onDevices);
    // 错误 SnackBar
    _errorSub = LanServiceAdapter.instance.watchErrors().listen(_onError);
  }

  void _onDevices(List<Device> devices) {
    if (!devices.any((d) => d.deviceId == widget.peerDeviceId)) {
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
    // Host 退出游戏时关闭房间
    LanServiceAdapter.instance.closeRoom(widget.roomId);
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
                  onRestart: _onRestart,
                  onExit: _onExit,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(GameState gs, BoardThemeData theme) {
    final isMyTurn = gs.currentPlayerIsTop; // host 是 top player
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
    // gs, isRunning, isMyTurn 来自参数

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cellSize = w / 11;
        final boardSize = w; // = cellSize * 11

        // 首次或 boardSize 变化时升级 touchController
        _ensureHostTouchController(boardSize);

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
                      flipY: true, // host 翻转
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
                      isTop: true,
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
                        icon: Icons.refresh,
                        label: '重新开始',
                        theme: theme,
                        onTap: () => _showResetConfirm(context, theme),
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

  void _ensureHostTouchController(double boardSize) {
    if (_touchController is! LanHostTouchController ||
        (_touchController as LanHostTouchController).boardSize != boardSize) {
      _touchController = LanHostTouchController(boardSize: boardSize);
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
      debugPrint('[HOST-CONFIRM] ENTER: phase=${toc.phase} pendingTarget=${toc.pendingTargetCellId} pendingWall=${toc.pendingWall} gsHistory.len=${gs.history.length} gsStatus=${gs.status}');
      if (toc.phase != TouchPhase.confirming) {
        debugPrint('[HOST-CONFIRM] EXIT: phase not confirming');
        return;
      }

      final current = _gameStateNotifier!.value;
      debugPrint('[HOST-CONFIRM] notifierNull=${_gameStateNotifier == null} currentPlayerIsTop=${current.currentPlayerIsTop}');
      GameState? result;
      if (toc.pendingWall != null) {
        final pw = toc.pendingWall!;
        debugPrint('[HOST-CONFIRM] try placeWall: x=${pw.x} y=${pw.y} o=${pw.o}');
        result = QuoridorEngine.placeWall(current, pw.x, pw.y, pw.o);
      } else {
        final cellId = toc.pendingTargetCellId ?? 0;
        debugPrint('[HOST-CONFIRM] try movePiece: cellId=$cellId');
        result = QuoridorEngine.movePiece(current, cellId);
      }
      if (result == null) {
        debugPrint('[HOST-CONFIRM] EXIT: result null (illegal move/wall)');
        toc.reset();
        setState(() {});
        return;
      }
      final next = QuoridorEngine.switchTurn(result);
      debugPrint('[HOST-CONFIRM] next.currentPlayerIsTop=${next.currentPlayerIsTop} notifier.value set');
      _gameStateNotifier!.value = next; // Session 自动 serialize + 发
      toc.reset();
      setState(() {});
    };
  }

  VoidCallback get _onCancel {
    return () {
      debugPrint('[HOST-CANCEL] BEFORE: phase=${_touchController.phase} pendingTarget=${_touchController.pendingTargetCellId} pendingWall=${_touchController.pendingWall}');
      _touchController.cancelAction();
      debugPrint('[HOST-CANCEL] AFTER: phase=${_touchController.phase} pendingTarget=${_touchController.pendingTargetCellId} pendingWall=${_touchController.pendingWall}');
      setState(() {});
    };
  }

  void _onRestart() {
    // 重置 GameState（Session 会自动 serialize + 推送给 Client，两端 overlay 消失）。
    // 不走 VM —— GamePage 的状态由 _gameStateNotifier + Session 驱动。
    _touchController.reset();
    _resetGameState();
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

  void _showResetConfirm(BuildContext context, BoardThemeData theme) {
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
            Icon(Icons.refresh,
                size: 32, color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text('重新开始',
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
                      _resetGameState();
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

  /// 重置 GameState 到初始状态（Session 会自动同步给对端）
  void _resetGameState() {
    _gameStateNotifier?.value = QuoridorEngine.initialize();
    setState(() {});
  }
}
