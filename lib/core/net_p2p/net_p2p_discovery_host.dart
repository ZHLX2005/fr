// lib/core/net_p2p/net_p2p_discovery_host.dart
//
// NetP2P 入口 — LAN 局域网发现 / Relay 互联网房间（v3 snapshot + Lua）

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_widget.dart';

import 'pages/net_p2p_chat_page.dart';
import 'pages/net_p2p_snapshot_chat.dart';

/// P2P 入口页面 — LAN 局域网发现 / Relay 互联网房间（v3 snapshot）
class NetP2PPage extends StatefulWidget {
  const NetP2PPage({super.key});
  @override
  State<NetP2PPage> createState() => _NetP2PPageState();
}

enum _Mode { lan, relay }

/// 聊天房间 Lua 脚本（v3 snapshot 驱动）
///
/// handlers 必须是 TOP-LEVEL GLOBALS，server 会按
/// `definition.functions` 列表注入并调用。
const String _defaultChatScript = r'''
on_init = function(c, p) c.messages = {}; return c end
on_join = function(c, p) return c end
on_action_CHAT = function(c, p) table.insert(c.messages, p); return c end
return {
  definition = { functions = { "on_init", "on_join", "on_action_CHAT" } },
  on_init = on_init,
  on_join = on_join,
  on_action_CHAT = on_action_CHAT,
}
''';

class _NetP2PPageState extends State<NetP2PPage> {
  _Mode _mode = _Mode.lan;

  // LAN 模式连接状态
  fw.Transport? _lanTransport;
  String? _lanMyNodeId;
  String? _lanPeerAlias;
  String? _lanSessionScope;

  // Relay v3 模式连接状态
  RoomHandle? _v3Room;

  @override
  void dispose() {
    _lanTransport?.stop();
    _v3Room?.dispose();
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

  // ——— Relay v3 模式 ———

  void _onV3RoomReady(RoomHandle handle) {
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
    if (_lanTransport != null && _lanSessionScope != null) {
      return NetP2PChatPage(
        transport: _lanTransport!,
        scope: _lanSessionScope!,
        myNodeId: _lanMyNodeId!,
        peerAlias: _lanPeerAlias ?? '对方',
        onLeave: _disconnect,
      );
    }
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
    return RelayV3Widget(
      relayUrl: 'http://47.110.80.47:8988',
      defaultScript: _defaultChatScript,
      defaultMaxPlayers: 2,
      title: 'P2P 聊天',
      onRoomReady: _onV3RoomReady,
    );
  }
}
