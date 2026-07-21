// lib/core/surround_game/lan/relay_lobby_page.dart
//
// 跨网络模式入口页 — 建房/加入选择 → 引擎 RelayDiscovery → 游戏页。

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
    super.dispose();
  }

  Future<void> _onPeerSelected(fw.DiscoveredPeer peer, fw.RelayTransport transport, {required bool isHost}) async {
    final alias = _aliasCtrl.text.trim();
    final adapter = LanServiceAdapter();
    adapter.attach(transport, alias: alias);

    final roomId = peer.address.replaceFirst('relay://', '');
    final room = GameRoom(
      roomId: roomId,
      hostId: isHost ? transport.myNodeId : peer.id,
      hostName: isHost ? alias : peer.alias,
    );
    if (isHost) {
      await adapter.createRoom(room);
    } else {
      adapter.joinGameScope(roomId);
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isHost
            ? LanHostGamePage(roomId: roomId, peerDeviceId: peer.id, adapter: adapter)
            : LanClientGamePage(roomId: roomId, hostDeviceId: peer.id, adapter: adapter),
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
            Text('跨网络对战',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: theme.btnText)),
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
            const SizedBox(height: 32),

            // 创建房间（房主）
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _enterRelay(isHost: true),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('创建房间（我是房主）'),
                style: FilledButton.styleFrom(backgroundColor: boardTheme.piecePlayerA),
              ),
            ),
            const SizedBox(height: 16),

            // 加入房间
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _enterRelay(isHost: false),
                icon: const Icon(Icons.login),
                label: const Text('加入房间（我是玩家）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enterRelay({required bool isHost}) async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请先输入名称');
      return;
    }
    await PlayerProfileService.saveAlias(alias);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RelayConnectPage(
          isHost: isHost,
          alias: alias,
          onPeerSelected: (peer, transport) =>
              _onPeerSelected(peer, transport, isHost: isHost),
          onError: _onError,
        ),
      ),
    );
  }
}

/// RelayDiscovery 包装页 — 持有 isHost 标志
class _RelayConnectPage extends StatefulWidget {
  final bool isHost;
  final String alias;
  final void Function(fw.DiscoveredPeer, fw.RelayTransport) onPeerSelected;
  final void Function(String) onError;

  const _RelayConnectPage({
    required this.isHost,
    required this.alias,
    required this.onPeerSelected,
    required this.onError,
  });

  @override
  State<_RelayConnectPage> createState() => _RelayConnectPageState();
}

class _RelayConnectPageState extends State<_RelayConnectPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isHost ? '创建房间' : '加入房间'),
      ),
      body: fw.RelayDiscovery(
        relayUrl: 'http://47.110.80.47:8988',
      ).buildPage(
        onPeerSelected: widget.onPeerSelected,
        onError: widget.onError,
      ),
    );
  }
}