// lib/core/surround_game/lan/lan_lobby_page.dart
//
// 局域网模式入口页 — 使用新引擎 Transport 直接发现/连接。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;
import '../board_theme.dart';
import 'game_room.dart';
import 'lan_room_page.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'persistence/player_profile_service.dart';
import 'service/lan_service_adapter.dart';

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
  fw.Transport? _transport;
  bool _started = false;
  String? _error;

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
  }

  Future<void> _startDiscovery() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入名称')),
      );
      return;
    }
    PlayerProfileService.saveAlias(alias);

    try {
      final transport = await fw.LanTransport.create();
      await transport.joinScope('peers');
      _adapter.attach(transport, alias: alias);
      if (!mounted) return;
      setState(() {
        _transport = transport;
        _started = true;
        _error = null;
      });
      _errorSub = _adapter.watchErrors().listen(_onError);
      _peerSub = _adapter.watchPeers().listen((peers) {
        if (mounted) setState(() => _peers = peers);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '启动失败: $e');
    }
  }

  void _onPeerTapped(String peerId) {
    final room = GameRoom.placeholder(roomId: 'sg-$peerId');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: room.roomId,
          role: 'client',
          initialRoom: room.copyWith(hostId: peerId, hostName: peerId.substring(0, 6)),
        ),
      ),
    );
  }

  Future<void> _createRoom() async {
    if (!_started) return;
    final vm = LanHostViewModel();
    vm.dispatch(const HostCreateRoomPressed());
    final state = vm.value;
    final roomId = state is HostWaiting ? state.room.roomId : 'host-room';
    await _adapter.createRoom(GameRoom.placeholder(roomId: roomId));
    vm.dispose();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: roomId,
          role: 'host',
          initialRoom: GameRoom.placeholder(roomId: roomId).copyWith(
            hostId: _adapter.myDeviceId,
            hostName: _adapter.myAlias,
          ),
        ),
      ),
    ).then((_) => _adapter.closeRoom(roomId));
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
    final theme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('局域网对局'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
        actions: [
          if (_started)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_peers.length} 设备',
                  style: TextStyle(color: theme.btnSub, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 别名
          _buildAliasField(theme),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ),

          // 未启动 → 引导按钮
          if (!_started)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_find, size: 64),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _aliasCtrl.text.trim().isEmpty ? null : _startDiscovery,
                      icon: const Icon(Icons.search),
                      label: const Text('发现设备'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.piecePlayerA,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('输入名称后开始搜索局域网设备',
                        style: TextStyle(color: theme.btnSub, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // 已启动 → 设备列表 + 创建房间
          if (_started) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _createRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('创建房间'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.piecePlayerA,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _peers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_find, size: 64, color: theme.btnSub),
                          const SizedBox(height: 16),
                          Text('等待设备上线...',
                              style: TextStyle(color: theme.btnSub)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _peers.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: Text('设备 ${_peers[i].substring(0, 6)}'),
                        subtitle: Text('ID: ${_peers[i]}'),
                        onTap: () => _onPeerTapped(_peers[i]),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAliasField(BoardThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 28,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _aliasCtrl,
                    focusNode: _focusNode,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: theme.btnText,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      hintText: '输入你的名称',
                      hintStyle: TextStyle(
                          color: theme.btnSub.withValues(alpha: 0.5),
                          fontSize: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: theme.btnBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: theme.btnBorder.withValues(alpha: 0.4))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                    maxLength: 16,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      PlayerProfileService.saveAlias(v.trim());
                    },
                    onEditingComplete: () {
                      PlayerProfileService.saveAlias(_aliasCtrl.text.trim());
                      _focusNode.unfocus();
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _started ? Colors.green : Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _started ? '已连接' : '未连接',
                      style: TextStyle(color: theme.btnSub, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
