import 'dart:async';

import 'package:flutter/material.dart';
import '../board_theme.dart';
import '../models/game_room.dart';
import 'lan_host_game_page.dart';
import 'lan_client_game_page.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'lan_client_view_model.dart';

/// 房间等待页面 — 同时支持 Host 和 Client 两种角色。
///
/// Host 进入时携带 [initialRoom]（已建房），
/// Client 进入时携带 [initialRoom]（目标房），会自动模拟 join → accept → 倒计时。
class LanRoomPage extends StatefulWidget {
  final String roomId;
  final String role;
  final GameRoom initialRoom;

  const LanRoomPage({
    super.key,
    required this.roomId,
    required this.role,
    required this.initialRoom,
  });

  @override
  State<LanRoomPage> createState() => _LanRoomPageState();
}

class _LanRoomPageState extends State<LanRoomPage> {
  LanHostViewModel? _hostVm;
  LanClientViewModel? _clientVm;

  bool get _isHost => widget.role == 'host';

  @override
  void initState() {
    super.initState();
    if (_isHost) {
      _hostVm = LanHostViewModel();
      _hostVm!.dispatch(HostCreateRoomWithRoom(widget.initialRoom));
    } else {
      _clientVm = LanClientViewModel();
      _simulateAutoJoin();
    }
  }

  @override
  void dispose() {
    _hostVm?.dispose();
    _clientVm?.dispose();
    super.dispose();
  }

  /// 桩化：Client 在 500ms 后自动加入房间
  void _simulateAutoJoin() {
    final roomId = widget.roomId;
    Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _clientVm?.dispatch(ClientJoinPressed(
        GameRoom.placeholder(roomId: roomId),
      ));
      // 模拟加入成功
      Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _clientVm?.dispatch(ClientJoinAccepted(
          GameRoom.placeholder(roomId: roomId),
        ));
        // 模拟主机开始倒计时
        Timer(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          _clientVm?.dispatch(const HostStartedCountdown(3));
        });
      });
    });
  }

  void _onBackPressed() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final boardTheme = BoardTheme.of(context);

    if (_isHost) {
      return ValueListenableBuilder<LanHostState>(
        valueListenable: _hostVm!,
        builder: (_, state, __) => _buildScaffold(
          boardTheme,
          content: switch (state) {
            HostWaiting() => _buildHostWaiting(state, boardTheme),
            HostCountdown(:final secondsLeft) =>
              _buildCountdown(state.room, secondsLeft, boardTheme),
            _ => _buildHostWaiting(
                HostWaiting(GameRoom.placeholder(roomId: widget.roomId)),
                boardTheme,
              ),
          },
        ),
      );
    } else {
      return ValueListenableBuilder<LanClientState>(
        valueListenable: _clientVm!,
        builder: (_, state, __) => _buildScaffold(
          boardTheme,
          content: switch (state) {
            ClientJoining() => _buildJoining(state, boardTheme),
            ClientWaiting() => _buildClientWaiting(state, boardTheme),
            ClientCountdown(:final secondsLeft) =>
              _buildCountdown(state.room, secondsLeft, boardTheme),
            _ => _buildClientWaiting(
                ClientWaiting(GameRoom.placeholder(roomId: widget.roomId)),
                boardTheme,
              ),
          },
        ),
      );
    }
  }

  Widget _buildScaffold(
    BoardThemeData theme, {
    required Widget content,
  }) {
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: Text('房间 ${widget.roomId}'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
      ),
      body: Center(child: content),
    );
  }

  /// Host 等待玩家加入
  Widget _buildHostWaiting(HostWaiting state, BoardThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          '等待玩家加入...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: theme.btnText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '房间号: ${state.room.roomId}',
          style: TextStyle(fontSize: 14, color: theme.btnSub),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => _hostVm!.dispatch(const HostStartGamePressed()),
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始游戏'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.piecePlayerA,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
        ),
      ],
    );
  }

  /// Client 等待主机开始
  Widget _buildClientWaiting(ClientWaiting state, BoardThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          '等待主机开始...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: theme.btnText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '房间号: ${state.room.roomId}',
          style: TextStyle(fontSize: 14, color: theme.btnSub),
        ),
      ],
    );
  }

  /// Client 正在加入
  Widget _buildJoining(ClientJoining state, BoardThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          '正在加入房间...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: theme.btnText,
          ),
        ),
      ],
    );
  }

  /// 倒计时页面 — Host 和 Client 共用
  Widget _buildCountdown(
    GameRoom room,
    int secondsLeft,
    BoardThemeData theme,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '游戏即将开始',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.btnText,
          ),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            '$secondsLeft',
            key: ValueKey(secondsLeft),
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: theme.piecePlayerA,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '房间号: ${room.roomId}',
          style: TextStyle(fontSize: 14, color: theme.btnSub),
        ),
        if (secondsLeft == 0) _buildAutoNavigate(),
      ],
    );
  }

  /// 倒计时结束自动跳转
  Widget _buildAutoNavigate() {
    // Use post-frame callback to navigate after build completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final page = _isHost
          ? LanHostGamePage(roomId: widget.roomId)
          : LanClientGamePage(roomId: widget.roomId);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => page),
      );
    });
    return const SizedBox.shrink();
  }
}
