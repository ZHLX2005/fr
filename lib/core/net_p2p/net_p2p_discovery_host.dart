// lib/core/net_p2p/net_p2p_discovery_host.dart
//
// NetP2P 入口 — LAN 局域网发现 / Relay 互联网房间（v3 Lua 状态机 + 大厅等待）

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/lan/lan_discovery.dart';
import 'package:xiaodouzi_fr/core/net_engine/lan/transport.dart';
import 'package:xiaodouzi_fr/core/net_engine/pages/net_engine_debug_page.dart';
import 'package:xiaodouzi_fr/core/net_engine/pages/net_engine_settings_page.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_widget.dart';

import 'pages/net_p2p_chat_page.dart';
import 'pages/net_p2p_snapshot_chat.dart';
import 'scripts/lobby_chat_script.dart';

/// P2P 入口页面 — LAN 局域网发现 / Relay 互联网房间（v3 Lua 状态机 + 大厅等待）
class NetP2PPage extends StatefulWidget {
  const NetP2PPage({super.key});
  @override
  State<NetP2PPage> createState() => _NetP2PPageState();
}

enum _Mode { lan, relay }

class _NetP2PPageState extends State<NetP2PPage> {
  _Mode _mode = _Mode.lan;

  // LAN 模式连接状态
  Transport? _lanTransport;
  String? _lanMyNodeId;
  String? _lanPeerAlias;
  String? _lanSessionScope;

  // Relay v3 模式（大厅 → 游戏）
  RoomHandle? _v3Room;

  @override
  void dispose() {
    _lanTransport?.stop();
    _v3Room?.dispose();
    super.dispose();
  }

  // ——— LAN 模式 ———

  void _onLanConnected(DiscoveredPeer peer, Transport transport) {
    final ids = [transport.myNodeId, peer.id];
    ids.sort();
    final scope = 'chat-${ids[0]}-${ids[1]}';
    transport.joinScope(scope);
    setState(() {
      _lanTransport = transport;
      _lanMyNodeId = transport.myNodeId;
      _lanPeerAlias = peer.alias;
      _lanSessionScope = scope;
    });
  }

  // ——— Relay v3 模式：大厅 → 聊天 ———

  void _onV3Started(RoomHandle handle) {
    setState(() => _v3Room = handle);
  }

  void _disconnect() {
    _lanTransport?.stop();
    _v3Room?.dispose();
    setState(() {
      _lanTransport = null;
      _lanMyNodeId = null;
      _lanPeerAlias = null;
      _lanSessionScope = null;
      _v3Room = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // LAN 聊天页
    if (_lanTransport != null && _lanSessionScope != null) {
      return NetP2PChatPage(
        transport: _lanTransport!,
        scope: _lanSessionScope!,
        myNodeId: _lanMyNodeId!,
        peerAlias: _lanPeerAlias ?? '对方',
        onLeave: _disconnect,
      );
    }
    // Relay v3 聊天页（大厅 → onV3Started → snapshot chat）
    if (_v3Room != null) {
      return NetP2PSnapshotChatPage(
        handle: _v3Room!,
        onLeave: _disconnect,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_mode == _Mode.lan ? '局域网发现' : '互联网房间'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NetEngineSettingsPage(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NetEngineDebugPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeSwitcher(),
          Expanded(child: _buildDiscoveryView()),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<_Mode>(
        segments: const [
          ButtonSegment(value: _Mode.lan, icon: Icon(Icons.wifi), label: Text('局域网')),
          ButtonSegment(value: _Mode.relay, icon: Icon(Icons.cloud), label: Text('跨网络')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
    );
  }

  Widget _buildDiscoveryView() {
    if (_mode == _Mode.lan) {
      return LanDiscovery().buildPage(
        onPeerSelected: _onLanConnected,
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('LAN 错误: $e')));
          }
        },
      );
    }
    // Relay v3 大厅（建房/加入 → lobby 等待 → 开始游戏）
    return RelayV3Lobby(
      relayUrl: 'http://47.110.80.47:8988',
      script: kLobbyChatScript,
      maxPlayers: 2,
      title: 'P2P 聊天',
      onStarted: _onV3Started,
    );
  }
}
