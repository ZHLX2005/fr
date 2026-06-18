// lib/core/surround_game/lan/lan_room_page.dart
//
// 房间等待页面 — 同时支持 Host 和 Client 两种角色。
//
// 本轮改造：
// - Host 进入：announceRoom + 订阅 room events 处理 ClientJoinRequested
// - Client 进入：sendJoinRequest 替代桩化 Timer
// - 双方收到 join result 后跳 GamePage
// - 删除 _simulateAutoJoin（桩化）
// - 倒计时由 Host 本地驱动，Client 跳 GamePage 不再走 HostStartedCountdown

import 'dart:async';

import 'package:flutter/material.dart';
import '../board_theme.dart';
import 'game_room.dart';
import 'lan_host_game_page.dart';
import 'lan_client_game_page.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'lan_client_view_model.dart';
import 'service/lan_service_adapter.dart';
import 'protocol/lan_messages.dart';

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
  StreamSubscription<LanRoomEvent>? _roomSub;
  String? _clientDeviceId; // 新增：缓存 Client 加入时的 deviceId
  // 标记：是否已通过 _onCountdownFinished 过渡到 GamePage。
  // dispose 据此区分「过渡到游戏」（不关房）与「放弃建房」（关房广播）。
  bool _navigatedToGame = false;

  bool get _isHost => widget.role == 'host';

  @override
  void initState() {
    super.initState();
    if (_isHost) {
      _hostVm = LanHostViewModel();
      _hostVm!.dispatch(HostCreateRoomWithRoom(widget.initialRoom));
      _startHost();
    } else {
      _clientVm = LanClientViewModel();
      _startClient();
    }
    _roomSub =
        LanServiceAdapter.instance.watchRoomEvents().listen(_onRoomEvent);
  }

  Future<void> _startHost() async {
    // 立即广播一次（adapter 内部每 5s 周期重发）
    await LanServiceAdapter.instance.announceRoom(widget.initialRoom);
  }

  Future<void> _startClient() async {
    // 发 join 请求
    await LanServiceAdapter.instance.sendJoinRequest(
      hostDeviceId: widget.initialRoom.hostId,
      clientAlias: LanServiceAdapter.instance.myAlias,
    );
  }

  void _onRoomEvent(LanRoomEvent ev) {
    if (!mounted) return;
    if (ev is ClientJoinRequested && _isHost) {
      // Host 收到 client 加入请求 → 接受 + dispatch
      // 简单验证：本机 hostId != clientDeviceId
      if (ev.clientDeviceId == LanServiceAdapter.instance.myDeviceId) {
        return; // 忽略自己
      }
      setState(() {
        _clientDeviceId = ev.clientDeviceId;
      });
      _hostVm?.dispatch(HostClientJoined(
        ev.clientDeviceId,
        ev.clientAlias,
      ));
      // 接受消息（由 sendJoinAccept 走协议通道）
      LanServiceAdapter.instance.sendJoinAccept(
        clientDeviceId: ev.clientDeviceId,
        room: widget.initialRoom.copyWith(
          clientId: ev.clientDeviceId,
          clientName: ev.clientAlias,
        ),
      );
    } else if (ev is ClientJoinResult && !_isHost) {
      // Client 收到 join 结果
      if (ev.accepted) {
        _clientVm?.dispatch(ClientJoinAccepted(widget.initialRoom));
        _onCountdownFinished();
      } else {
        _clientVm?.dispatch(ClientJoinRejected(ev.reason ?? '拒绝'));
      }
    } else if (ev is HostRoomClosed && !_isHost) {
      // Host 关房 → 弹提示并退出
      _clientVm?.dispatch(ClientJoinRejected('Host 关闭了房间'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host 关闭了房间')),
        );
        Navigator.of(context).pop();
      }
    }
    // 本轮 YAGNI：不监听 HostStatePushed（它是 LanClientEvent，不是 LanRoomEvent）。
    // Client 跳 GamePage 由 Host 端倒计时结束后通过游戏状态通道（Task 16/17）触发，
    // 或作为兜底由 _buildAutoNavigate 在 secondsLeft==0 跳。
  }

  void _onCountdownFinished() {
    if (!mounted) return;
    // 标记已过渡到 GamePage：dispose 时据此跳过 stopRoom（关房由 GamePage.dispose 负责）。
    _navigatedToGame = true;
    final page = _isHost
        ? LanHostGamePage(
            roomId: widget.roomId,
            peerDeviceId: _clientDeviceId ?? '',
          )
        : LanClientGamePage(
            roomId: widget.roomId, hostDeviceId: widget.initialRoom.hostId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _hostVm?.dispose();
    _clientVm?.dispose();
    // Host 从 RoomPage 跳到 GamePage（pushReplacement）是合法过渡，不关房——
    // 关房由 LanHostGamePage.dispose 负责（host 真正退出游戏时）。
    // 但若 Host 未进入游戏就返回（放弃建房），必须 stopRoom：否则 announce timer
    // 会泄漏，房间一直在其他设备的列表里「挂着不销毁」。
    if (_isHost && !_navigatedToGame) {
      LanServiceAdapter.instance.stopRoom(widget.roomId);
    }
    super.dispose();
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

  Widget _buildHostWaiting(HostWaiting state, BoardThemeData theme) {
    final joined = state.room.clientId != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          joined ? '玩家已加入' : '等待玩家加入...',
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
        if (joined)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '对手: ${state.room.clientName ?? "?"}',
              style: TextStyle(fontSize: 14, color: theme.btnSub),
            ),
          ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: joined
              ? () => _hostVm!.dispatch(const HostStartGamePressed())
              : null,
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

  Widget _buildAutoNavigate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onCountdownFinished();
    });
    return const SizedBox.shrink();
  }
}
