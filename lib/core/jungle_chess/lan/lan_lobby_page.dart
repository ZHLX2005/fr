// lib/core/jungle_chess/lan/lan_lobby_page.dart
//
// 局域网模式入口页 — 使用新引擎 Transport 直接发现/连接。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'lan_room_page.dart';
import 'persistence/player_profile_service.dart';
import 'protocol/lan_messages.dart';
import 'service/lan_service_adapter.dart';
import 'game_room.dart';

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  final _adapter = LanServiceAdapter.instance;
  final _aliasCtrl = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<LanServiceError>? _errorSub;
  StreamSubscription<List<String>>? _peerSub;
  List<String> _peers = [];
  List<HostRoomAnnounced> _rooms = [];
  fw.Transport? _transport;
  bool _started = false;

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
    if (savedAlias != null && savedAlias.isNotEmpty) {
      _aliasCtrl.text = savedAlias;
    }
    _errorSub = _adapter.watchErrors().listen(_onError);
    _peerSub = _adapter.watchPeers().listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
  }

  Future<void> _startDiscovery() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) return;
    PlayerProfileService.saveAlias(alias);

    try {
      final transport = await fw.LanTransport.create();
      await transport.joinScope('peers');
      _adapter.attach(transport, alias: alias);
      if (!mounted) return;
      setState(() { _transport = transport; _started = true; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动失败: $e')),
        );
      }
    }
  }

  void _onCreateRoom() {
    if (!_started) return;
    final roomId = DateTime.now().millisecondsSinceEpoch.toString();
    final vm = LanHostViewModel();
    vm.dispatch(HostCreateRoom(roomId: roomId, hostName: _adapter.myAlias));
    final room = GameRoom(
      roomId: roomId,
      hostDeviceId: _adapter.myDeviceId,
      hostName: _adapter.myAlias,
    );
    _adapter.announceRoom(room);
    vm.dispose();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: roomId,
          role: 'host',
          initialRoom: room,
        ),
      ),
    ).then((_) => _adapter.stopRoom(roomId));
  }

  void _onJoinRoom(HostRoomAnnounced ann) {
    final room = GameRoom(
      roomId: ann.roomId,
      hostDeviceId: ann.hostDeviceId,
      hostName: ann.hostName,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: ann.roomId,
          role: 'client',
          initialRoom: room,
        ),
      ),
    );
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _peerSub?.cancel();
    _focusNode.dispose();
    _aliasCtrl.dispose();
    _adapter.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('斗兽棋 - 局域网'),
        actions: [
          if (_started)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text('${_peers.length} 设备', style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 别名
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                const Icon(Icons.person, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _aliasCtrl,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      hintText: '输入名称',
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 16,
                    onSubmitted: (v) => PlayerProfileService.saveAlias(v.trim()),
                  ),
                ),
                const SizedBox(width: 12),
                if (!_started)
                  FilledButton(
                    onPressed: _aliasCtrl.text.trim().isEmpty ? null : _startDiscovery,
                    child: const Text('发现'),
                  ),
              ],
            ),
          ),

          if (_started)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _onCreateRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('创建房间'),
                ),
              ),
            ),

          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_started) {
      return Center(
        child: Text('输入名称后点击"发现"',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    if (_peers.isEmpty) {
      return Center(
        child: Text('等待设备上线...',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return ListView.builder(
      itemCount: _peers.length,
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.phone_android),
        title: Text('设备 ${_peers[i].substring(0, 6)}'),
        subtitle: Text('ID: ${_peers[i]}'),
      ),
    );
  }
}
