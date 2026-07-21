import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transport.dart';
import '../lan/lan_transport.dart';

/// LAN 发现 — 没有抽象，直接具体 widget
///
/// **自己的认证**：UDP 心跳（无需认证）
///
/// **自己的设置**：deviceAlias / multicastPort / multicastAddress 由
/// [buildSettingsPage] 渲染并独立持久化，业务层零配置代码。
class LanDiscovery {
  LanDiscovery({
    this.multicastPort = 5678,
    this.multicastAddress = '239.255.255.255',
  });

  final int multicastPort;
  final String multicastAddress;

  /// 当前生效的 deviceAlias（从 SharedPreferences 读，懒加载）
  Future<String> getAlias() => _LanPrefs.getAlias();

  /// 构建发现页面 — 业务层直接渲染
  ///
  /// [onPeerSelected] 会带回 widget 内部已创建好的 [Transport]，
  /// 业务层直接用，**不需要自己 create**。Transport 所有权在回调后
  /// 转移给业务层，业务层负责 stop()。
  Widget buildPage({
    required void Function(DiscoveredPeer peer, Transport transport) onPeerSelected,
    void Function(String error)? onError,
  }) {
    return _LanDiscoveryPage(
      multicastPort: multicastPort,
      multicastAddress: multicastAddress,
      onPeerSelected: onPeerSelected,
      onError: onError,
    );
  }

  /// 构建设置页面 — 业务层直接渲染
  ///
  /// 暴露：
  /// - deviceAlias（共享给 Relay）
  /// - multicastPort / multicastAddress（LAN 内部）
  Widget buildSettingsPage({VoidCallback? onSaved}) {
    return _LanSettingsPage(
      multicastPort: multicastPort,
      multicastAddress: multicastAddress,
      onSaved: onSaved,
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

/// LAN 设置持久化（私有 key，biz 不感知）
class _LanPrefs {
  static const _kAlias = 'localnet.lan.alias';

  static Future<String> getAlias() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAlias) ?? 'Flutter Device';
  }

  static Future<void> setAlias(String alias) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAlias, alias);
  }
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
  final void Function(DiscoveredPeer peer, Transport transport) onPeerSelected;
  final void Function(String error)? onError;

  @override
  State<_LanDiscoveryPage> createState() => _LanDiscoveryPageState();
}

class _LanDiscoveryPageState extends State<_LanDiscoveryPage> {
  final Map<String, DiscoveredPeer> _peers = {};
  String? _myNodeId;
  String? _error;
  Transport? _transport;
  bool _handedOff = false;

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
    // transport 所有权已转移给业务层 → 不 stop；否则泄漏
    if (!_handedOff) _transport?.stop();
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
                              onTap: () {
                                final t = _transport;
                                if (t == null) return;
                                _handedOff = true;
                                widget.onPeerSelected(p, t);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// LAN 设置页面 — 由 LanDiscovery.buildSettingsPage() 渲染
class _LanSettingsPage extends StatefulWidget {
  const _LanSettingsPage({
    required this.multicastPort,
    required this.multicastAddress,
    this.onSaved,
  });

  final int multicastPort;
  final String multicastAddress;
  final VoidCallback? onSaved;

  @override
  State<_LanSettingsPage> createState() => _LanSettingsPageState();
}

class _LanSettingsPageState extends State<_LanSettingsPage> {
  final _aliasCtrl = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final alias = await _LanPrefs.getAlias();
    if (!mounted) return;
    setState(() {
      _aliasCtrl.text = alias;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _LanPrefs.setAlias(_aliasCtrl.text.trim());
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
        Text('局域网', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wifi),
                  title: const Text('多播端口'),
                  subtitle: Text('${widget.multicastPort}'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.router),
                  title: const Text('多播地址'),
                  subtitle: Text(widget.multicastAddress),
                ),
                const SizedBox(height: 8),
                Text(
                  '多播端口/地址在 LanDiscovery() 构造时固定，'
                  '运行时修改需要重新创建 transport。',
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