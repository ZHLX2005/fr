// lib/core/surround_game/lan/relay_lobby_page.dart
//
// 跨网络模式入口页 — 直接使用引擎 RelayDiscovery widget。
// RelayDiscovery 处理房间创建 + 等待 + WebSocket 通信。

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;
import '../board_theme.dart';
import 'game_room.dart';
import 'lan_host_game_page.dart';
import 'lan_client_game_page.dart';
import 'persistence/player_profile_service.dart';
import 'service/lan_service_adapter.dart';

class RelayLobbyPage extends StatefulWidget {
  const RelayLobbyPage({super.key});

  @override
  State<RelayLobbyPage> createState() => _RelayLobbyPageState();
}

class _RelayLobbyPageState extends State<RelayLobbyPage> {
  final _aliasCtrl = TextEditingController();
  final _roomCodeCtrl = TextEditingController();
  bool _isLobby = true;
  bool _isBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    PlayerProfileService.loadAlias().then((alias) {
      if (mounted && alias != null) {
        setState(() => _aliasCtrl.text = alias);
      }
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _roomCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enterRelay() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请先输入名称');
      return;
    }
    await PlayerProfileService.saveAlias(alias);
    setState(() {
      _isLobby = false;
      _error = null;
    });
  }

  Future<void> _onPeerSelected(fw.DiscoveredPeer peer, fw.RelayTransport transport) async {
    final alias = _aliasCtrl.text.trim();
    final adapter = LanServiceAdapter.instance;
    adapter.attach(transport, alias: alias);

    final roomId = peer.address.replaceFirst('relay://', '');
    final room = GameRoom(
      roomId: roomId,
      hostId: peer.id,
      hostName: peer.alias,
    );
    await adapter.createRoom(room);

    if (!mounted) return;
    // RelayDiscovery 的 peer.id 是 'relay:<code>'，host 是建房者
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LanClientGamePage(roomId: roomId, hostDeviceId: peer.id, adapter: adapter),
      ),
    );
  }

  void _onError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final boardTheme = BoardTheme.of(context);

    if (_isLobby) {
      return Scaffold(
        backgroundColor: theme.boardSurface,
        appBar: AppBar(
          title: const Text('跨网络对局'),
          backgroundColor: theme.panelBg,
          foregroundColor: theme.btnText,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud, size: 64, color: boardTheme.piecePlayerA),
              const SizedBox(height: 24),
              Text('跨网络对战', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: theme.btnText)),
              const SizedBox(height: 16),
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
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _enterRelay,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('进入中继房间'),
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

    // 已进入中继 → 直接渲染 RelayDiscovery widget
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('跨网络对局'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
      ),
      body: fw.RelayDiscovery(
        relayUrl: 'http://47.110.80.47:8988',
      ).buildPage(
        onPeerSelected: _onPeerSelected,
        onError: _onError,
      ),
    );
  }
}