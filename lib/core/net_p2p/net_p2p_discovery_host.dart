// lib/core/net_p2p/net_p2p_discovery_host.dart
//
// NetP2P 入口 — LAN 局域网发现 + Relay 互联网房间

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;

import 'pages/net_p2p_chat_page.dart';

/// biz 入口页面 — LAN 局域网发现 / Relay 互联网房间
class NetP2PPage extends StatefulWidget {
  const NetP2PPage({super.key});
  @override
  State<NetP2PPage> createState() => _NetP2PPageState();
}

enum _Mode { lan, relay }

class _NetP2PPageState extends State<NetP2PPage> {
  _Mode _mode = _Mode.lan;

  // 连接后
  fw.Transport? _transport;
  String? _myNodeId;
  String? _peerAlias;
  String? _sessionScope;

  @override
  void dispose() {
    _transport?.stop();
    super.dispose();
  }

  /// LAN 模式：LanDiscovery 完成握手后回调
  void _onLanConnected(fw.DiscoveredPeer peer, fw.Transport transport) {
    _onConnected(transport, peer.id, peer.alias);
  }

  /// Relay 模式：RelayDiscovery 完成握手后回调
  void _onRelayConnected(fw.DiscoveredPeer peer, fw.RelayTransport transport) {
    _onConnected(transport, peer.id, peer.alias);
  }

  void _onConnected(fw.Transport transport, String peerId, String peerAlias) {
    // 用排序后的 nodeId 拼 scope
    final ids = [transport.myNodeId, peerId];
    ids.sort();
    final scope = 'chat-${ids[0]}-${ids[1]}';
    transport.joinScope(scope);
    setState(() {
      _transport = transport;
      _myNodeId = transport.myNodeId;
      _peerAlias = peerAlias;
      _sessionScope = scope;
    });
  }

  void _disconnect() {
    _transport?.stop();
    setState(() {
      _transport = null;
      _myNodeId = null;
      _peerAlias = null;
      _sessionScope = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_transport != null && _sessionScope != null) {
      return NetP2PChatPage(
        transport: _transport!,
        scope: _sessionScope!,
        myNodeId: _myNodeId!,
        peerAlias: _peerAlias ?? '对方',
        onLeave: _disconnect,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetP2P'),
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
          ButtonSegment(
            value: _Mode.lan,
            icon: Icon(Icons.wifi),
            label: Text('局域网'),
          ),
          ButtonSegment(
            value: _Mode.relay,
            icon: Icon(Icons.cloud),
            label: Text('跨网络'),
          ),
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
    return fw.RelayDiscovery(
      relayUrl: 'http://47.110.80.47:8988',
    ).buildPage(
      onPeerSelected: _onRelayConnected,
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Relay 错误: $e')),
          );
        }
      },
    );
  }
}
