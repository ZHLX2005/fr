import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../relay/relay_transport.dart';
import '../lan/lan_discovery.dart' show DiscoveredPeer;

/// Relay 发现 — 没有抽象，直接具体 widget
///
/// **自己的认证**：房间号（输入或创建）
///
/// **自己的设置**：deviceAlias / relayUrl 由
/// [buildSettingsPage] 渲染并独立持久化，业务层零配置代码。
class RelayDiscovery {
  RelayDiscovery({required this.relayUrl});

  final String relayUrl;

  /// 构建发现页面 — 业务层直接渲染
  ///
  /// [onPeerSelected] 会带回 widget 内部已 createRoom/joinRoom 后的
  /// [RelayTransport]，业务层直接用，**不需要自己 create**。
  /// Transport 所有权在回调后转移给业务层，业务层负责 stop()。
  Widget buildPage({
    required void Function(DiscoveredPeer peer, RelayTransport transport) onPeerSelected,
    void Function(String error)? onError,
  }) {
    return _RelayDiscoveryPage(
      relayUrl: relayUrl,
      onPeerSelected: onPeerSelected,
      onError: onError,
    );
  }

  /// 构建设置页面 — 业务层直接渲染
  ///
  /// 暴露：
  /// - deviceAlias（与 LAN 共享，独立 key）
  /// - relayUrl（中继服务器地址）
  Widget buildSettingsPage({VoidCallback? onSaved}) {
    return _RelaySettingsPage(
      relayUrl: relayUrl,
      onSaved: onSaved,
    );
  }
}

/// Relay 设置持久化（私有 key，biz 不感知）
class _RelayPrefs {
  static const _kAlias = 'localnet.relay.alias';
  static const _kRelayUrl = 'localnet.relay.url';

  static Future<String> getAlias() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAlias) ?? 'Flutter Device';
  }

  static Future<void> setAlias(String alias) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAlias, alias);
  }

  static Future<String?> getRelayUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRelayUrl);
  }

  static Future<void> setRelayUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRelayUrl, url);
  }
}

class _RelayDiscoveryPage extends StatefulWidget {
  const _RelayDiscoveryPage({
    required this.relayUrl,
    required this.onPeerSelected,
    this.onError,
  });

  final String relayUrl;
  final void Function(DiscoveredPeer peer, RelayTransport transport) onPeerSelected;
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
  bool _handedOff = false;
  String _alias = 'Flutter Device';

  bool get _inRoom => _roomCode != null;

  @override
  void initState() {
    super.initState();
    _loadAlias();
  }

  Future<void> _loadAlias() async {
    final alias = await _RelayPrefs.getAlias();
    if (!mounted) return;
    setState(() => _alias = alias);
  }

  @override
  void dispose() {
    _roomCodeCtrl.dispose();
    // transport 所有权已转移给业务层 → 不 stop；否则泄漏
    if (!_handedOff) _transport?.stop();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await RelayTransport.create(
        relayUrl: widget.relayUrl,
        alias: _alias,
      );
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
      final t = await RelayTransport.create(
        relayUrl: widget.relayUrl,
        alias: _alias,
      );
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
    final t = _transport;
    if (t == null) return;
    _handedOff = true;
    widget.onPeerSelected(
      DiscoveredPeer(
        id: 'relay:$code',
        alias: 'Host',
        address: 'relay://$code',
      ),
      t,
    );
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

/// Relay 设置页面 — 由 RelayDiscovery.buildSettingsPage() 渲染
class _RelaySettingsPage extends StatefulWidget {
  const _RelaySettingsPage({
    required this.relayUrl,
    this.onSaved,
  });

  final String relayUrl;
  final VoidCallback? onSaved;

  @override
  State<_RelaySettingsPage> createState() => _RelaySettingsPageState();
}

class _RelaySettingsPageState extends State<_RelaySettingsPage> {
  final _aliasCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final alias = await _RelayPrefs.getAlias();
    final url = await _RelayPrefs.getRelayUrl();
    if (!mounted) return;
    setState(() {
      _aliasCtrl.text = alias;
      _urlCtrl.text = url ?? widget.relayUrl;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _RelayPrefs.setAlias(_aliasCtrl.text.trim());
    await _RelayPrefs.setRelayUrl(_urlCtrl.text.trim());
    if (!mounted) return;
    widget.onSaved?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('设备身份', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _aliasCtrl,
              decoration: const InputDecoration(
                labelText: '设备名称',
                hintText: '对端看到的名字',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('中继服务器', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'http://47.110.80.47:8988',
                    prefixIcon: Icon(Icons.cloud_outlined),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                Text(
                  '修改后需要重新创建 transport 才能生效。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('保存'),
        ),
      ],
    );
  }
}