import 'package:flutter/material.dart';

import '../relay/relay_transport.dart';
import '../lan/lan_discovery.dart' show DiscoveredPeer;

/// Relay 发现 — 没有抽象，直接具体 widget
///
/// **自己的认证**：房间号（输入或创建）
class RelayDiscovery {
  RelayDiscovery({required this.relayUrl});

  final String relayUrl;

  /// 构建发现页面 — 业务层直接渲染
  Widget buildPage({
    required void Function(DiscoveredPeer peer) onPeerSelected,
    void Function(String error)? onError,
  }) {
    return _RelayDiscoveryPage(
      relayUrl: relayUrl,
      onPeerSelected: onPeerSelected,
      onError: onError,
    );
  }
}

class _RelayDiscoveryPage extends StatefulWidget {
  const _RelayDiscoveryPage({
    required this.relayUrl,
    required this.onPeerSelected,
    this.onError,
  });

  final String relayUrl;
  final void Function(DiscoveredPeer peer) onPeerSelected;
  final void Function(String error)? onError;

  @override
  State<_RelayDiscoveryPage> createState() => _RelayDiscoveryPageState();
}

class _RelayDiscoveryPageState extends State<_RelayDiscoveryPage> {
  final _roomCodeCtrl = TextEditingController();
  RelayTransport? _transport;
  String? _roomCode;
  String? _error;
  bool _busy = false;

  bool get _inRoom => _roomCode != null;

  @override
  void dispose() {
    _roomCodeCtrl.dispose();
    _transport?.stop();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await RelayTransport.create(relayUrl: widget.relayUrl);
      final code = await t.createRoom();
      await t.joinScope('peers');
      _transport = t;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _roomCode = code;
      });
      _autoNavigate(code);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '创建房间失败: $e';
        });
        widget.onError?.call(_error!);
      }
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位房间号');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await RelayTransport.create(relayUrl: widget.relayUrl);
      await t.joinRoom(code);
      await t.joinScope('peers');
      _transport = t;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _roomCode = code;
      });
      _autoNavigate(code);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '加入房间失败: $e';
        });
        widget.onError?.call(_error!);
      }
    }
  }

  void _autoNavigate(String code) {
    widget.onPeerSelected(DiscoveredPeer(
      id: 'relay:$code',
      alias: 'Host',
      address: 'relay://$code',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('跨网络发现')),
      body: _inRoom ? _buildRoomPanel() : _buildLobbyPanel(),
    );
  }

  Widget _buildLobbyPanel() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud, size: 64),
          const SizedBox(height: 24),
          Text('中继: ${widget.relayUrl}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _createRoom,
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline),
              label: Text(_busy ? '创建中...' : '创建房间'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('或')),
              Expanded(child: Divider()),
            ]),
          ),
          TextField(
            controller: _roomCodeCtrl,
            decoration: const InputDecoration(
              hintText: '输入 6 位房间号',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            maxLength: 6,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _joinRoom(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _joinRoom,
              icon: const Icon(Icons.login),
              label: Text(_busy ? '加入中...' : '加入房间'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomPanel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('已加入房间: $_roomCode', style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              _transport?.stop();
              _transport = null;
              setState(() => _roomCode = null);
            },
            child: const Text('离开'),
          ),
        ],
      ),
    );
  }
}