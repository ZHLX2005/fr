import 'package:flutter/material.dart';

import '../transport.dart';
import '../lan/lan_transport.dart';

/// LAN 发现 — 没有抽象，直接具体 widget
///
/// **自己的认证**：UDP 心跳（无需认证）
class LanDiscovery {
  LanDiscovery({this.multicastPort = 5678, this.multicastAddress = '239.255.255.255'});

  final int multicastPort;
  final String multicastAddress;

  /// 构建发现页面 — 业务层直接渲染
  Widget buildPage({
    required void Function(DiscoveredPeer peer) onPeerSelected,
    void Function(String error)? onError,
  }) {
    return _LanDiscoveryPage(
      multicastPort: multicastPort,
      multicastAddress: multicastAddress,
      onPeerSelected: onPeerSelected,
      onError: onError,
    );
  }
}

/// LAN 发现到的对端
class DiscoveredPeer {
  DiscoveredPeer({required this.id, required this.alias, required this.address});
  final String id;
  final String alias;
  final String address;
}

class _LanDiscoveryPage extends StatefulWidget {
  const _LanDiscoveryPage({
    required this.multicastAddress,
    required this.multicastPort,
    required this.onPeerSelected,
    this.onError,
  });

  final String multicastAddress;
  final int multicastPort;
  final void Function(DiscoveredPeer peer) onPeerSelected;
  final void Function(String error)? onError;

  @override
  State<_LanDiscoveryPage> createState() => _LanDiscoveryPageState();
}

class _LanDiscoveryPageState extends State<_LanDiscoveryPage> {
  final Map<String, DiscoveredPeer> _peers = {};
  String? _myNodeId;
  String? _error;
  Transport? _transport;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final transport = await LanTransport.create(
        multicastAddress: widget.multicastAddress,
        multicastPort: widget.multicastPort,
      );
      _transport = transport;
      _myNodeId = transport.myNodeId;

      // 监听事件总线：peer-joined-scope 表示新节点出现
      transport.events.listen((e) {
        if (e.topic == 'peer-joined-scope') {
          final from = e.data['from'] as String?;
          if (from != null && mounted) {
            setState(() {
              _peers[from] = DiscoveredPeer(
                id: from,
                alias: from.substring(0, 6),
                address: 'lan://$from',
              );
            });
          }
        }
      });

      // 加入 'peers' scope 自动同步
      await transport.joinScope('peers');

      if (mounted) setState(() {});
    } catch (e) {
      _error = '启动失败: $e';
      widget.onError?.call(_error!);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _transport?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('局域网发现')),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : Column(
              children: [
                if (_myNodeId != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('我的 ID: ${_myNodeId!.substring(0, 8)}'),
                  ),
                const Divider(),
                Expanded(
                  child: _peers.isEmpty
                      ? const Center(child: Text('搜索设备中...'))
                      : ListView.builder(
                          itemCount: _peers.length,
                          itemBuilder: (_, i) {
                            final p = _peers.values.elementAt(i);
                            return ListTile(
                              title: Text(p.alias),
                              subtitle: Text(p.address),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => widget.onPeerSelected(p),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}