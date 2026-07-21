// lib/core/surround_game/lan/lan_lobby_page.dart
//
// 局域网模式入口页 — 直接使用引擎 LanDiscovery widget。
// LanDiscovery 处理发现 + HTTP 三次握手，transport 已经是双向可信任。

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;
import '../board_theme.dart';
import 'game_room.dart';
import 'lan_host_game_page.dart';
import 'lan_client_game_page.dart';
import 'persistence/player_profile_service.dart';
import 'protocol/lan_messages.dart';
import 'service/lan_service_adapter.dart';

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  final _aliasCtrl = TextEditingController();
  bool _started = false;
  bool _handedOff = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    PlayerProfileService.loadAlias().then((alias) {
      if (mounted && alias != null && alias.isNotEmpty) {
        setState(() => _aliasCtrl.text = alias);
      }
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    // 注意：路由跳转后 lobby 被销毁，detach 由 game page 接管。
    // 如果用户从 lobby 直接退出（没进游戏），adapter 才会被 detach。
    if (_started && !_handedOff) {
      LanServiceAdapter.instance.detach();
    }
    super.dispose();
  }

  Future<void> _startDiscovery() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请先输入名称');
      return;
    }
    await PlayerProfileService.saveAlias(alias);
    setState(() {
      _started = true;
      _error = null;
    });
  }

  Future<void> _onPeerSelected(fw.DiscoveredPeer peer, fw.Transport transport) async {
    final alias = _aliasCtrl.text.trim();
    final adapter = LanServiceAdapter.instance;
    adapter.attach(transport, alias: alias);

    // 构造房间 ID（基于双方 nodeId 排序）
    final roomId = _computeRoomId(transport.myNodeId, peer.id);
    final room = GameRoom(
      roomId: roomId,
      hostId: transport.myNodeId, // 谁先邀请谁是 host
      hostName: alias,
      clientId: peer.id,
      clientName: peer.alias,
    );
    await adapter.createRoom(room);

    if (!mounted) return;
    final isHost = transport.myNodeId.compareTo(peer.id) < 0;
    setState(() => _handedOff = true);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isHost
            ? LanHostGamePage(roomId: roomId, peerDeviceId: peer.id, adapter: adapter)
            : LanClientGamePage(roomId: roomId, hostDeviceId: peer.id, adapter: adapter),
      ),
    );
  }

  String _computeRoomId(String a, String b) {
    final ids = [a, b]..sort();
    return 'sg-${ids[0]}-${ids[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final boardTheme = BoardTheme.of(context);

    if (!_started) {
      return Scaffold(
        backgroundColor: theme.boardSurface,
        appBar: AppBar(
          title: const Text('局域网对局'),
          backgroundColor: theme.panelBg,
          foregroundColor: theme.btnText,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi, size: 64),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _aliasCtrl,
                  decoration: const InputDecoration(
                    hintText: '输入你的名称',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  maxLength: 16,
                  onSubmitted: (_) => _startDiscovery(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _startDiscovery,
                icon: const Icon(Icons.search),
                label: const Text('开始发现设备'),
                style: FilledButton.styleFrom(
                  backgroundColor: boardTheme.piecePlayerA,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 发现已启动 → 直接渲染 LanDiscovery widget
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('局域网对局'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
      ),
      body: fw.LanDiscovery().buildPage(
        onPeerSelected: _onPeerSelected,
        onError: (err) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        },
      ),
    );
  }
}