// lib/core/net_p2p/net_p2p_discovery_host.dart
//
// NetP2P 入口 — LAN 局域网发现 / Relay 互联网房间（快照模式）

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;
import 'package:xiaodouzi_fr/core/net_engine/relay_snapshot/relay_snapshot_transport.dart';

import 'pages/net_p2p_chat_page.dart';
import 'pages/net_p2p_snapshot_chat.dart';

/// P2P 入口页面 — LAN 局域网发现 / Relay 互联网房间（快照）
class NetP2PPage extends StatefulWidget {
  const NetP2PPage({super.key});
  @override
  State<NetP2PPage> createState() => _NetP2PPageState();
}

enum _Mode { lan, relay }

class _NetP2PPageState extends State<NetP2PPage> {
  _Mode _mode = _Mode.lan;

  // LAN 模式连接状态
  fw.Transport? _lanTransport;
  String? _lanMyNodeId;
  String? _lanPeerAlias;
  String? _lanSessionScope;

  // Relay 快照模式连接状态
  RelaySnapshotTransport? _snapshotTransport;
  RoomHandle? _snapshotRoom;
  bool _inSnapshotChat = false;

  @override
  void dispose() {
    _lanTransport?.stop();
    _snapshotRoom?.dispose();
    _snapshotTransport?.close();
    super.dispose();
  }

  // ——— LAN 模式 ———

  void _onLanConnected(fw.DiscoveredPeer peer, fw.Transport transport) {
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

  // ——— Relay 快照模式 ———

  Future<void> _onSnapshotRelayRoomReady(fw.RelayTransport transport, String code) async {
    // 拿到 transport 后改用快照协议重连（独立链路）
    final snap = RelaySnapshotTransport(
      relayUrl: 'http://47.110.80.47:8988',
      alias: '我',
    );
    final handle = await snap.joinRoom(code);
    if (!mounted) {
      await handle.dispose();
      snap.close();
      return;
    }
    transport.close(); // 关闭旧 v1 transport
    setState(() {
      _snapshotTransport = snap;
      _snapshotRoom = handle;
      _inSnapshotChat = true;
    });
  }

  void _disconnect() {
    _lanTransport?.stop();
    _snapshotRoom?.dispose();
    _snapshotTransport?.close();
    setState(() {
      _lanTransport = null;
      _lanMyNodeId = null;
      _lanPeerAlias = null;
      _lanSessionScope = null;
      _snapshotRoom = null;
      _snapshotTransport = null;
      _inSnapshotChat = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_lanTransport != null && _lanSessionScope != null) {
      return NetP2PChatPage(
        transport: _lanTransport!,
        scope: _lanSessionScope!,
        myNodeId: _lanMyNodeId!,
        peerAlias: _lanPeerAlias ?? '对方',
        onLeave: _disconnect,
      );
    }
    if (_inSnapshotChat && _snapshotRoom != null && _snapshotTransport != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('快照聊天')),
        body: NetP2PSnapshotChatPage(
          handle: _snapshotRoom!,
          myDeviceId: _snapshotTransport!.deviceId,
          onLeave: _disconnect,
        ),
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
                builder: (_) => fw.NetEngineSettingsPage(
                  mode: _mode == _Mode.lan ? fw.MessageNetMode.lan : fw.MessageNetMode.relay,
                  relayUrl: 'http://47.110.80.47:8988',
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const fw.NetEngineDebugPage()),
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
      return fw.LanDiscovery().buildPage(
        onPeerSelected: _onLanConnected,
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('LAN 错误: $e')));
          }
        },
      );
    }
    return fw.RelayRoomWidget(
      relayUrl: 'http://47.110.80.47:8988',
      defaultMaxPlayers: 2,
      maxPlayersRange: const [2],
      title: 'P2P 聊天',
      onRoomReady: _onSnapshotRelayRoomReady,
    );
  }
}