// lib/core/jungle_chess/lan/lan_room_page.dart
//
// 房间等待页面 — 同时支持 Host 和 Client 两种角色。
//
// Host 进入：announceRoom + 订阅 room events 处理 ClientJoinRequested
// Client 进入：sendJoinRequest + 订阅 room events 处理 ClientJoinResult
// 双方收到 join result 后跳 GamePage
// 倒计时由 Host 本地驱动

import 'dart:async';

import 'package:flutter/material.dart';
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
  String? _clientDeviceId;
  bool _navigatedToGame = false;
  int _countdown = -1;
  Timer? _countdownTimer;

  bool get _isHost => widget.role == 'host';

  @override
  void initState() {
    super.initState();
    if (_isHost) {
      _hostVm = LanHostViewModel();
      _hostVm!.dispatch(HostCreateRoom(
        roomId: widget.roomId,
        hostName: widget.initialRoom.hostName,
      ));
      _startHost();
    } else {
      _clientVm = LanClientViewModel();
      _startClient();
    }
    _roomSub =
        LanServiceAdapter.instance.watchRoomEvents().listen(_onRoomEvent);
  }

  Future<void> _startHost() async {
    // already announced from lobby
  }

  Future<void> _startClient() async {
    LanServiceAdapter.instance.joinGameScope(widget.roomId);
  }

  void _onRoomEvent(LanRoomEvent ev) {
    if (!mounted) return;
    if (ev is ClientJoinRequested && _isHost) {
      if (ev.clientDeviceId == LanServiceAdapter.instance.myDeviceId) {
        return;
      }
      setState(() {
        _clientDeviceId = ev.clientDeviceId;
      });
      LanServiceAdapter.instance.acceptJoin(ev.clientDeviceId);
      _startCountdown();
    } else if (ev is ClientJoinResult && !_isHost) {
      if (ev.accepted) {
        _startCountdown();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加入被拒: ${ev.rejectReason ?? "未知原因"}')),
          );
          Navigator.of(context).pop();
        }
      }
    } else if (ev is HostRoomClosed && !_isHost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host 关闭了房间')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _startCountdown() {
    if (_countdownTimer != null) return;
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown = _countdown - 1);
      if (_countdown <= 0) {
        t.cancel();
        _onCountdownFinished();
      }
    });
  }

  void _onCountdownFinished() {
    if (!mounted) return;
    _navigatedToGame = true;
    final page = _isHost
        ? LanHostGamePage(
            viewModel: _hostVm!,
            peerDeviceId: _clientDeviceId ?? '',
            roomId: widget.roomId,
          )
        : LanClientGamePage(
            viewModel: _clientVm!,
          );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _roomSub?.cancel();
    _hostVm?.dispose();
    _clientVm?.dispose();
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
    if (_countdown >= 0) {
      return _buildScaffold(
        content: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '游戏即将开始',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Text(
                '$_countdown',
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_isHost) {
      return ValueListenableBuilder<LanHostState>(
        valueListenable: _hostVm!,
        builder: (_, state, __) => _buildScaffold(
          content: switch (state) {
            HostWaiting() => _buildHostWaiting(state),
            HostCountdown(:final secondsLeft) =>
              _buildCountdown(state.room, secondsLeft),
            _ => _buildHostWaiting(
                HostWaiting(room: widget.initialRoom),
              ),
          },
        ),
      );
    } else {
      return ValueListenableBuilder<LanClientState>(
        valueListenable: _clientVm!,
        builder: (_, state, __) => _buildScaffold(
          content: switch (state) {
            ClientJoining() => _buildJoining(),
            ClientWaiting() => _buildClientWaiting(state),
            _ => _buildClientWaiting(
                ClientWaiting(room: widget.initialRoom),
              ),
          },
        ),
      );
    }
  }

  Widget _buildScaffold({required Widget content}) {
    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${widget.roomId}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
      ),
      body: Center(child: content),
    );
  }

  Widget _buildHostWaiting(HostWaiting state) {
    final joined = state.room.hasClient;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          joined ? '玩家已加入' : '等待玩家加入...',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text('房间号: ${state.room.roomId}'),
        if (joined && state.room.clientName != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('对手: ${state.room.clientName}'),
          ),
      ],
    );
  }

  Widget _buildClientWaiting(ClientWaiting state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          '等待主机开始...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text('房间号: ${state.room.roomId}'),
      ],
    );
  }

  Widget _buildJoining() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          '正在加入房间...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildCountdown(GameRoom room, int secondsLeft) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '游戏即将开始',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        Text(
          '$secondsLeft',
          style: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }
}
