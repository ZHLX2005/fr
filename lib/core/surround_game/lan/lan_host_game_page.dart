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
import 'package:xiaodouzi_fr/core/surround_game/lan/service/lan_service_adapter.dart';
import '../board_theme.dart';
import '../surround_game_constants.dart';
import '../widgets/player_panel.dart';
import '../widgets/touch_controller.dart';
import '../engine/game_engine.dart';
import '../models/game_room.dart';
import '../models/game_state.dart';
import '../local/local_match_state.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'widgets/lan_board_stack.dart';
import 'widgets/touch_controller_factory.dart';

/// LAN 主机游戏页面
///
/// 单面板布局：棋盘居中（flipY=true 翻转，host 是 top player 视觉在下方），
/// 底部仅显示 host 自己的 PlayerPanel。
/// touchController 使用 [LanHostTouchControllerFactory] 创建，带 y 坐标镜像。
class LanHostGamePage extends StatefulWidget {
  final String roomId;
  final String peerDeviceId;

  const LanHostGamePage({super.key, required this.roomId, required this.peerDeviceId});

  @override
  State<LanHostGamePage> createState() => _LanHostGamePageState();
}

class _LanHostGamePageState extends State<LanHostGamePage> {
  late final LanHostViewModel _viewModel;
  TouchController _touchController = TouchController();
  ValueNotifier<GameState>? _gameStateNotifier;
  StreamSubscription<GameState>? _gameStateSub;

  @override
  void initState() {
    super.initState();
    _viewModel = LanHostViewModel();
    _viewModel.attachPeer(widget.peerDeviceId);
    // 跳过倒计时：LanRoomPage 已经跑完 3s 倒计时，这里直接 fast-forward 到 HostInGame。
    // 1) HostLobby -> HostWaiting（需要一个 GameRoom 才能接 StartGamePressed）
    _viewModel.dispatch(HostCreateRoomWithRoom(
      GameRoom.placeholder(roomId: widget.roomId),
    ));
    // 2) HostWaiting -> HostCountdown(3)
    _viewModel.dispatch(const HostStartGamePressed());
    // 3) HostCountdown(3) -> (2) -> (1) -> (0) -> HostInGame（4 次 tick）
    for (var i = 0; i < 4; i++) {
      _viewModel.dispatch(const HostTick());
    }
    _gameStateNotifier = ValueNotifier<GameState>(QuoridorEngine.initialize());
    // Host 不创建 Session（Client 端不监听 session channel，Session 在此冗余）。
    // 双方统一走显式 sendGameState / watchGameState 路径，避免异步发送与
    // Client 回送交错导致 _gameStateNotifier 被旧 state 覆盖、回合错乱。
    _gameStateSub = LanServiceAdapter.instance
        .watchGameState(widget.peerDeviceId)
        .listen((gs) {
      if (!mounted) return;
      _gameStateNotifier!.value = gs;
      // 同步给 VM（让 VM 的 HostInGame.gameState 跟上 Client 推来的 state），
      // 否则 Host 下次 dispatch HostMoveCommitted 时会用 VM 里旧的 state 算 next，
      // 丢弃 Client 的走子导致棋盘回退。
      if (_viewModel.value is HostInGame ||
          _viewModel.value is HostFinished) {
        _viewModel.dispatch(HostGameStatePushed(gs));
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _gameStateSub?.cancel();
    _gameStateNotifier?.dispose();
    _touchController.reset();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: ValueListenableBuilder<LanHostState>(
          valueListenable: _viewModel,
          builder: (_, state, __) => switch (state) {
            HostInGame() => _buildGameScreen(
                state,
                theme,
              ),
            HostFinished(:final result) => _buildGameScreen(
                state,
                theme,
                overlay: _buildVictoryOverlay(_gameStateNotifier!.value, result, theme),
              ),
            _ => _buildIdleScreen(theme),
          },
        ),
      ),
    );
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

  Widget _buildIdleScreen(BoardThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_esports, size: 64, color: theme.piecePlayerA),
          const SizedBox(height: 16),
          Text(
            'LAN 主机',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.btnText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '房间 ${widget.roomId}',
            style: TextStyle(fontSize: 14, color: theme.btnSub),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _viewModel.dispatch(const HostStartGamePressed()),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始游戏'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.piecePlayerA,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameScreen(
    LanHostState state,
    BoardThemeData theme, {
    Widget? overlay,
  }) {
    final gs = _gameStateNotifier!.value;
    final isRunning = state is HostInGame || state is HostFinished;
    final isMyTurn = gs.currentPlayerIsTop; // host 是 top player
    debugPrint('[HOST-GAME-SCREEN] build: currentPlayerIsTop=${gs.currentPlayerIsTop} isMyTurn=$isMyTurn topWalls=${gs.topWallsPlaced} bottomWalls=${gs.bottomWallsPlaced} history.len=${gs.history.length}');

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
            if (overlay != null) overlay,
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
      if (toc.phase != TouchPhase.confirming) return;

      int? wx, wy;
      WallOrientation? wo;
      if (toc.pendingWall != null) {
        wx = toc.pendingWall!.x;
        wy = toc.pendingWall!.y;
        wo = toc.pendingWall!.o;
      }

      debugPrint('[HOST-CONFIRM] BEFORE dispatch: phase=${toc.phase} pendingWall=${toc.pendingWall} mode=${toc.mode} notifier.currentPlayerIsTop=${_gameStateNotifier!.value.currentPlayerIsTop}');
      _viewModel.dispatch(HostMoveCommitted((
        toc.pendingTargetCellId ?? 0, wx, wy, wo,
      )));
      // 显式 sendGameState 到 'surround/game/state' 通道，让 Client watchGameState 收到。
      // 不依赖 Session（Client 端不监听 session channel）。
      final currentState = _viewModel.value;
      final newState = currentState is HostInGame
          ? currentState.gameState
          : currentState is HostFinished
              ? currentState.finalState
              : null;
      debugPrint('[HOST-CONFIRM] AFTER dispatch: VM type=${currentState.runtimeType} newState.currentPlayerIsTop=${newState?.currentPlayerIsTop} topWalls=${newState?.topWallsPlaced}');
      if (newState != null) {
        _gameStateNotifier!.value = newState;
        LanServiceAdapter.instance.sendGameState(
          hostDeviceId: widget.peerDeviceId,
          state: newState,
        );
      }
      toc.reset();
      setState(() {});
      debugPrint('[HOST-CONFIRM] AFTER setState: notifier.currentPlayerIsTop=${_gameStateNotifier!.value.currentPlayerIsTop} toc.phase=${toc.phase} toc.mode=${toc.mode}');
    };
  }

  VoidCallback get _onCancel {
    return () {
      _touchController.cancelAction();
      setState(() {});
    };
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
                      _viewModel.dispatch(const HostAbortGame());
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
                      _viewModel.dispatch(const HostAbortGame());
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

  // ═══════════════════ Victory overlay ═══════════════════

  Widget _buildVictoryOverlay(
    GameState finalState,
    GameResult result,
    BoardThemeData theme,
  ) {
    final isTopWin = result == GameResult.topWin;
    final winColor = isTopWin ? theme.piecePlayerA : theme.piecePlayerB;
    final winLabel = isTopWin ? '上方获胜！' : '下方获胜！';

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: theme.panelBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events, size: 48, color: winColor),
              const SizedBox(height: 12),
              Text(winLabel,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: winColor)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  _touchController.reset();
                  _viewModel.dispatch(const HostAbortGame());
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: winColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
