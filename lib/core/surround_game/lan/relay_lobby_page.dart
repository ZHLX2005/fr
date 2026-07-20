// lib/core/surround_game/lan/relay_lobby_page.dart
//
// 网络对局入口页 — 通过房间号发现对端，底层走 WS 通讯。
//
// 与 LanLobbyPage 共享同一份 LanServiceAdapter（按 TransportKind 分发）。
// 适配器自动处理 Relay 模式：createChatRoom → joinChatRoom → WS 通道。

import 'dart:async';

import 'package:flutter/material.dart';
import '../board_theme.dart';
import 'game_room.dart';
import 'lan_host_view_model.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_room_page.dart';
import 'persistence/player_profile_service.dart';
import 'service/lan_service_adapter.dart';
import 'protocol/lan_messages.dart';
import '../../localnet/transport/transport_kind.dart';

class RelayLobbyPage extends StatefulWidget {
  const RelayLobbyPage({super.key});

  @override
  State<RelayLobbyPage> createState() => _RelayLobbyPageState();
}

class _RelayLobbyPageState extends State<RelayLobbyPage> {
  final _adapter = LanServiceAdapter.instance;
  final _aliasCtrl = TextEditingController();
  final _roomCodeCtrl = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<LanRoomEvent>? _roomSub;
  StreamSubscription<LanServiceError>? _errorSub;
  bool _adapterStarted = false;
  bool _isBusy = false;
  String? _error;

  bool get _inRoom => _adapter.currentRoomCode != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final savedAlias = await PlayerProfileService.loadAlias();
    if (!mounted) return;

    _aliasCtrl.text = savedAlias ?? '';

    try {
      await _adapter.start(myAlias: savedAlias, kind: TransportKind.relay);
      if (!mounted) return;
      setState(() => _adapterStarted = true);
      _roomSub = _adapter.watchRoomEvents().listen(_onRoomEvent);
      _errorSub = _adapter.watchErrors().listen(_onError);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '启动失败: $e');
      }
    }

    if (savedAlias == null || savedAlias.isEmpty) {
      _focusNode.requestFocus();
    }
  }

  void _onAliasSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    PlayerProfileService.saveAlias(trimmed);
    _adapter.updateAlias(trimmed);
  }

  void _onRoomEvent(LanRoomEvent ev) {
    // Relay 模式下房间事件主要用于处理加入结果
    if (ev is ClientJoinResult && ev.accepted && mounted) {
      // 加入成功，自动导航到房间页
    }
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  Future<void> _createRoom() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final hostVm = LanHostViewModel();
      hostVm.dispatch(const HostCreateRoomPressed());
      final state = hostVm.value;
      final roomId = state is HostWaiting ? state.room.roomId : 'new-${DateTime.now().millisecondsSinceEpoch}';
      final room = GameRoom.placeholder(roomId: roomId);
      final code = await _adapter.createRoom(room);
      hostVm.dispose();
      if (!mounted) return;
      setState(() => _isBusy = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LanRoomPage(
            roomId: code,
            role: 'host',
            initialRoom: room.copyWith(hostId: _adapter.myDeviceId, hostName: _adapter.myAlias),
          ),
        ),
      ).then((_) {
        // 从房间页返回时关闭连接
        _adapter.closeRoom(code);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = '创建房间失败: $e';
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位房间号');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      // Relay 模式：通过房间号加入
      await _adapter.joinRelayRoom(code,
        hostDeviceId: 'relay',
        hostAlias: 'Host',
      );
      if (!mounted) return;
      setState(() => _isBusy = false);

      // 加入成功，跳转房间等待页
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LanRoomPage(
            roomId: code,
            role: 'client',
            initialRoom: GameRoom(
              roomId: code,
              hostId: 'relay',
              hostName: 'Host',
            ),
          ),
        ),
      ).then((_) {
        _adapter.closeRoom(code);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = '加入房间失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _errorSub?.cancel();
    _aliasCtrl.dispose();
    _roomCodeCtrl.dispose();
    _focusNode.dispose();
    if (_adapterStarted) {
      _adapter.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('网络对局'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud, size: 64, color: theme.piecePlayerA),
            const SizedBox(height: 24),
            Text(
              '跨网络对战',
              style: textTheme.titleLarge?.copyWith(color: theme.btnText),
            ),
            const SizedBox(height: 8),
            Text(
              '通过中继服务器实现远程联机',
              style: textTheme.bodySmall?.copyWith(color: theme.btnSub),
            ),
            const SizedBox(height: 32),

            // 别名
            if (!_adapterStarted || _aliasCtrl.text.isEmpty) ...[
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _aliasCtrl,
                  focusNode: _focusNode,
                  style: TextStyle(color: theme.btnText),
                  decoration: InputDecoration(
                    hintText: '输入你的名称',
                    hintStyle: TextStyle(color: theme.btnSub.withValues(alpha: 0.5)),
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person, color: theme.btnSub),
                  ),
                  maxLength: 16,
                  onSubmitted: _onAliasSubmitted,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 创建房间
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: (_adapterStarted && !_isBusy) ? _createRoom : null,
                icon: _isBusy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_circle_outline),
                label: Text(_isBusy ? '创建中...' : '创建房间'),
                style: FilledButton.styleFrom(backgroundColor: theme.piecePlayerA),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('或', style: TextStyle(color: Colors.grey)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),

            // 房间号输入
            SizedBox(
              width: 200,
              child: TextField(
                controller: _roomCodeCtrl,
                style: TextStyle(color: theme.btnText, letterSpacing: 4),
                decoration: InputDecoration(
                  hintText: '输入 6 位房间号',
                  hintStyle: TextStyle(color: theme.btnSub.withValues(alpha: 0.5)),
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key, color: theme.btnSub),
                ),
                maxLength: 6,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _joinRoom(),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: (_adapterStarted && !_isBusy) ? _joinRoom : null,
                icon: const Icon(Icons.login),
                label: Text(_isBusy ? '加入中...' : '加入房间'),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
