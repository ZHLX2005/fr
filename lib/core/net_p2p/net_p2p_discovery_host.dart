// lib/core/net_p2p/net_p2p_discovery_host.dart
//
// NetP2P 入口 — LAN 局域网发现 / Relay 互联网房间

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;

import 'pages/net_p2p_chat_page.dart';

/// P2P 入口页面 — LAN 局域网发现 / Relay 互联网房间
class NetP2PPage extends StatefulWidget {
  const NetP2PPage({super.key});
  @override
  State<NetP2PPage> createState() => _NetP2PPageState();
}

enum _Mode { lan, relay }

class _NetP2PPageState extends State<NetP2PPage> {
  _Mode _mode = _Mode.lan;

  // 连接后（LAN 模式使用 scope chat，Relay 模式通过 RelayRoomWidget 交付）
  fw.Transport? _transport;
  String? _myNodeId;
  String? _peerAlias;
  String? _sessionScope;

  // Relay 模式通过 RelayRoomWidget 交付后直接推送到这里
  fw.RelayTransport? _relayTransport;
  bool _inRelayChat = false;

  @override
  void dispose() {
    _transport?.stop();
    _relayTransport?.close();
    super.dispose();
  }

  // ——— LAN 模式 ———

  void _onLanConnected(fw.DiscoveredPeer peer, fw.Transport transport) {
    final ids = [transport.myNodeId, peer.id];
    ids.sort();
    final scope = 'chat-${ids[0]}-${ids[1]}';
    transport.joinScope(scope);
    setState(() {
      _transport = transport;
      _myNodeId = transport.myNodeId;
      _peerAlias = peer.alias;
      _sessionScope = scope;
    });
  }

  // ——— Relay 模式 ———

  void _onRelayRoomReady(fw.RelayTransport transport, String code) {
    setState(() {
      _relayTransport = transport;
      _myNodeId = transport.myNodeId;
      _inRelayChat = true;
    });
  }

  void _disconnect() {
    _transport?.stop();
    _relayTransport?.close();
    setState(() {
      _transport = null;
      _relayTransport = null;
      _myNodeId = null;
      _peerAlias = null;
      _sessionScope = null;
      _inRelayChat = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // LAN 聊天中
    if (_transport != null && _sessionScope != null) {
      return NetP2PChatPage(
        transport: _transport!,
        scope: _sessionScope!,
        myNodeId: _myNodeId!,
        peerAlias: _peerAlias ?? '对方',
        onLeave: _disconnect,
      );
    }
    // Relay 聊天中
    if (_inRelayChat && _relayTransport != null) {
      return _buildRelayChat();
    }

    // 模式选择 + 发现视图
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('LAN 错误: $e')),
            );
          }
        },
      );
    }
    // Relay 模式：使用 RelayRoomWidget（含参与者圆环大厅）
    return fw.RelayRoomWidget(
      relayUrl: 'http://47.110.80.47:8988',
      defaultMaxPlayers: 2,
      maxPlayersRange: const [2],
      title: 'P2P 聊天',
      onRoomReady: _onRelayRoomReady,
    );
  }

  Widget _buildRelayChat() {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('聊天中'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.close), onPressed: _disconnect, tooltip: '断开'),
        ],
      ),
      body: NetP2PChatPage(
        transport: _relayTransport!,
        scope: 'room/${_relayTransport!.roomInfo?.code ?? ''}/events',
        myNodeId: _myNodeId!,
        peerAlias: '对方',
        onLeave: _disconnect,
      ),
    );
  }
}
