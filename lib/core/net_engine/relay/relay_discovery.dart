import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../relay/relay_transport.dart';
import '../transport.dart';
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
  String _effectiveRelayUrl = '';
  bool _waitingForPeer = false;

  bool get _inRoom => _roomCode != null;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final alias = await _RelayPrefs.getAlias();
    final url = await _RelayPrefs.getRelayUrl();
    if (!mounted) return;
    setState(() {
      _alias = alias;
      _effectiveRelayUrl = url ?? widget.relayUrl;
    });
  }

  @override
  void dispose() {
    _roomCodeCtrl.dispose();
    _presenceSub?.cancel();
    if (!_handedOff) _transport?.stop();
    super.dispose();
  }

  StreamSubscription<DataLog>? _presenceSub;

  /// 进入等待状态：在房间 scope 上写入 presence，监听对端
  void _enterWaiting(RelayTransport t, String code, String status) {
    final scope = 'room-$code';
    t.joinScope(scope);
    _writePresence(t, scope, t.myNodeId, _alias, status);
    _presenceSub?.cancel();
    _presenceSub = t.watchScope(scope).listen((log) {
      _checkPresence(log.state, t);
    });
    // 订阅后立即检查：对端已写 presence 的场景（晚加入方）
    final log = t.getScope(scope);
    if (log != null) _checkPresence(log.state, t);
    setState(() {
      _waitingForPeer = true;
      _error = null;
    });
  }

  void _checkPresence(Map<String, dynamic> state, RelayTransport t) {
    if (!_waitingForPeer || _handedOff || !mounted) return;
    final code = _roomCode;
    final myId = t.myNodeId;
    if (code == null) return;
    for (final entry in state.entries) {
      if (!entry.key.startsWith('presence-') || entry.key == 'presence-$myId') continue;
      final data = entry.value as Map?;
      if (data == null) continue;
      final did = data['deviceId'] as String?;
      if (did == null || did == t.myNodeId) continue;
      final status = data['status'] as String? ?? '';

      if (status == 'joining') {
        // 我是 host，对方加入了 → 回传 ready（三次握手）
        _writePresence(t, 'room-$code', myId, _alias, 'ready');
        _completeHandshake(t, code, did, data['alias'] as String? ?? '?');
      } else if (status == 'ready') {
        // 我是 joiner，收到 host 的 ready → 完成
        _completeHandshake(t, code, did, data['alias'] as String? ?? '?');
      }
      return;
    }
  }

  void _completeHandshake(RelayTransport t, String code, String did, String alias) {
    _handedOff = true;
    _presenceSub?.cancel();
    // 协商角色：建房者（调用了 createRoom 的）= host，加入者 = client
    // _roomCode != null 表示当前 Discovery 实例是建房者
    if (_roomCode != null) {
      t.setRole(NodeRole.host);
      t.setPeerRole(NodeRole.client);
    } else {
      t.setRole(NodeRole.client);
      t.setPeerRole(NodeRole.host);
    }
    t.setPeerNodeId(did);
    widget.onPeerSelected(
      DiscoveredPeer(id: did, alias: alias, address: 'relay://$code'),
      t,
    );
  }

  /// 往 scope DataLog 写入 presence（持久化，对端晚加入也能读到）
  void _writePresence(RelayTransport t, String scope, String deviceId, String alias, String status) {
    final log = t.getScope(scope);
    if (log == null) return;
    log.merge({'presence-$deviceId': {'deviceId': deviceId, 'alias': alias, 'status': status}},
        localNodeId: deviceId);
    t.broadcastScope(scope);
    // events 路径辅助即时投递
    t.sendEvent(scope, 'presence', {'deviceId': deviceId, 'alias': alias, 'status': status});
  }

  Future<void> _createRoom() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = await RelayTransport.create(
        relayUrl: _effectiveRelayUrl,
        alias: _alias,
      );
      final code = await t.createRoomCompat();
      await t.joinScope('peers');
      _transport = t;
      if (!mounted) return;
      setState(() { _busy = false; _roomCode = code; });
      _enterWaiting(t, code, 'waiting'); // 房主
    } catch (e) {
      if (mounted) {
        setState(() { _busy = false; _error = '创建房间失败: $e'; });
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
    setState(() { _busy = true; _error = null; });
    try {
      final t = await RelayTransport.create(
        relayUrl: _effectiveRelayUrl,
        alias: _alias,
      );
      await t.joinRoomCompat(code);
      await t.joinScope('peers');
      _transport = t;
      if (!mounted) return;
      setState(() { _busy = false; _roomCode = code; });
      _enterWaiting(t, code, 'joining'); // 加入者
    } catch (e) {
      if (mounted) {
        setState(() { _busy = false; _error = '加入房间失败: $e'; });
        widget.onError?.call(_error!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('跨网络发现')),
      body: _inRoom ? _buildRoomPanel() : _buildLobbyPanel(),
    );
  }

  Widget _buildLobbyPanel() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 头部标识
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.cloud, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('跨网络连接',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Text('中继: $_effectiveRelayUrl',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 创建房间
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
                ],
              ),
            ),
          ),

          // 或
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(children: [
              const Expanded(child: Divider()),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('或',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    )),
              ),
              const Expanded(child: Divider()),
            ]),
          ),

          // 加入房间
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _roomCodeCtrl,
                    decoration: InputDecoration(
                      hintText: '输入 6 位房间号',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: const Icon(Icons.vpn_key),
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
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.login),
                      label: Text(_busy ? '加入中...' : '加入房间'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: theme.colorScheme.errorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomPanel() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 56, color: Colors.green),
                const SizedBox(height: 16),
                Text('已加入房间',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$_roomCode',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: theme.colorScheme.onPrimaryContainer,
                      )),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () {
                    _transport?.stop();
                    _transport = null;
                    setState(() => _roomCode = null);
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('离开房间'),
                ),
              ],
            ),
          ),
        ),
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