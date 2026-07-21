import 'dart:async';

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
///
/// **节能**：widget 挂载时不自动扫描，用户点击"扫描"按钮后才创建 transport。
/// 扫描完成后（选中 peer / 返回）transport 自动 stop，防止泄漏和耗电。
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
  static const _kMulticastPort = 'localnet.lan.port';
  static const _kMulticastAddress = 'localnet.lan.address';

  static Future<String> getAlias() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kAlias) ?? 'Flutter Device';
  }

  static Future<void> setAlias(String alias) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAlias, alias);
  }

  static Future<int> getMulticastPort() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kMulticastPort) ?? 5678;
  }

  static Future<void> setMulticastPort(int port) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMulticastPort, port);
  }

  static Future<String> getMulticastAddress() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kMulticastAddress) ?? '239.255.255.255';
  }

  static Future<void> setMulticastAddress(String addr) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMulticastAddress, addr);
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
  bool _scanning = false;
  bool _handedOff = false;
  String _myAlias = '';
  int _effectivePort = 5678;
  String _effectiveAddress = '239.255.255.255';
  bool _waitingForPeer = false;
  DiscoveredPeer? _waitingPeer;
  String? _sessionScope;
  DiscoveredPeer? _inviteFrom; // 别人邀请我

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final alias = await _LanPrefs.getAlias();
    final port = await _LanPrefs.getMulticastPort();
    final addr = await _LanPrefs.getMulticastAddress();
    if (!mounted) return;
    setState(() {
      _myAlias = alias;
      _effectivePort = port;
      _effectiveAddress = addr;
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    if (!_handedOff) _transport?.stop();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
      _peers.clear();
      _waitingForPeer = false;
      _waitingPeer = null;
      _inviteFrom = null;
    });

    try {
      if (!_handedOff) await _transport?.stop();
      _handedOff = false;

      final transport = await LanTransport.create(
        multicastAddress: _effectiveAddress,
        multicastPort: _effectivePort,
      );
      _transport = transport;
      _myNodeId = transport.myNodeId;

      transport.events.listen((e) {
        if (!mounted) return;
        // 设备发现
        if (e.topic == 'peer-joined-scope') {
          final from = e.data['from'] as String?;
          if (from != null) {
            setState(() {
              _peers[from] = DiscoveredPeer(
                id: from,
                alias: from.substring(0, 6),
                address: 'lan://$from',
              );
            });
          }
        }
        // 收到邀请 — 别人想和我对战
        if (e.topic == 'invite') {
          final target = e.data['targetDeviceId'] as String?;
          if (target == transport.myNodeId) {
            final fromId = e.data['from'] as String?;
            if (fromId != null) {
              setState(() {
                _inviteFrom = DiscoveredPeer(
                  id: fromId,
                  alias: e.data['alias'] as String? ?? fromId.substring(0, 6),
                  address: 'lan://$fromId',
                );
              });
            }
          }
        }
        // presence — 等待中的对端上线了（events 路径）
        if (e.topic == 'presence' && _waitingForPeer) {
          final did = e.data['deviceId'] as String?;
          if (did != null && did != transport.myNodeId) {
            // 通过 DataLog 路径触发 _checkPresence（已订阅 _presenceSub）
          }
        }
      });

      await transport.joinScope('peers');
      if (mounted) setState(() {});
    } catch (e) {
      _error = '扫描失败: $e';
      widget.onError?.call(_error!);
      if (mounted) setState(() {});
    }
  }

  void _stopScan() {
    _presenceSub?.cancel();
    if (!_handedOff) {
      _transport?.stop();
      _transport = null;
    }
    setState(() {
      _scanning = false;
      _myNodeId = null;
      _peers.clear();
      _waitingForPeer = false;
      _waitingPeer = null;
      _sessionScope = null;
      _inviteFrom = null;
    });
  }

  /// 主动邀请对方
  void _sendInvite(DiscoveredPeer p) {
    final t = _transport;
    final myId = _myNodeId;
    if (t == null || myId == null) return;

    // 发送邀请事件（所有人在 peers scope 都能收到）
    t.sendEvent('peers', 'invite', {
      'from': myId,
      'alias': _myAlias,
      'targetDeviceId': p.id,
    });

    // 接入 session scope
    final ids = [myId, p.id];
    ids.sort();
    _sessionScope = 'session-${ids[0]}-${ids[1]}';
    t.joinScope(_sessionScope!);
    _watchPresenceScope(t, _sessionScope!);

    // 用 DataLog 广播自身 presence（持久化，对端晚到也能读到）
    _writePresence(t, _sessionScope!, myId, _myAlias, 'inviting');

    setState(() {
      _waitingForPeer = true;
      _waitingPeer = p;
      _error = null;
    });
  }

  /// 接受别人的邀请
  void _acceptInvite() {
    final t = _transport;
    final myId = _myNodeId;
    final inviter = _inviteFrom;
    if (t == null || myId == null || inviter == null) return;

    final ids = [myId, inviter.id];
    ids.sort();
    _sessionScope = 'session-${ids[0]}-${ids[1]}';
    t.joinScope(_sessionScope!);
    _watchPresenceScope(t, _sessionScope!);
    _writePresence(t, _sessionScope!, myId, _myAlias, 'accepted');

    setState(() {
      _waitingForPeer = true;
      _waitingPeer = inviter;
      _inviteFrom = null;
    });
  }

  /// 往 scope DataLog 写入 presence（持久化，对端 join scope 后能读到）
  void _writePresence(Transport t, String scope, String deviceId, String alias, String status) {
    final log = t.getScope(scope);
    if (log == null) return;
    log.merge({'presence-$deviceId': {'deviceId': deviceId, 'alias': alias, 'status': status}},
        localNodeId: deviceId);
    t.broadcastScope(scope);
    // events 路径辅助即时投递
    t.sendEvent(scope, 'presence', {'deviceId': deviceId, 'alias': alias, 'status': status});
  }

  /// 监听 session scope DataLog — 对端 presence 出现即确认
  StreamSubscription<DataLog>? _presenceSub;
  void _watchPresenceScope(Transport t, String scope) {
    _presenceSub?.cancel();
    _presenceSub = t.watchScope(scope).listen((log) {
      _checkPresence(log.state, t);
    });
    // 订阅后立即检查：对端 presence 可能已被 _dispatch 预写入
    final log = t.getScope(scope);
    if (log != null) _checkPresence(log.state, t);
  }

  /// 三次握手检测
  void _checkPresence(Map<String, dynamic> state, Transport t) {
    if (!_waitingForPeer || _handedOff || !mounted) return;
    final wp = _waitingPeer;
    final myId = _myNodeId;
    final scope = _sessionScope;
    if (wp == null || myId == null || scope == null) return;

    final other = state['presence-${wp.id}'] as Map?;
    if (other == null) return;
    final otherStatus = other['status'] as String? ?? '';

    if (otherStatus == 'accepted') {
      // 我是邀请方，对方接受了 → 回传 confirmed（第三次握手）
      _writePresence(t, scope, myId, _myAlias, 'confirmed');
      _completeHandshake(wp, t);
    } else if (otherStatus == 'confirmed') {
      // 我是接受方，收到对方的 confirmed → 完成
      _completeHandshake(wp, t);
    }
    // otherStatus == 'inviting' → 我是接受方，等对方 confirmed，不处理
  }

  void _completeHandshake(DiscoveredPeer peer, Transport t) {
    _handedOff = true;
    _presenceSub?.cancel();
    widget.onPeerSelected(peer, t);
  }

  void _onPeerPresent(String deviceId, Transport transport) {
    final wp = _waitingPeer;
    if (wp == null || deviceId != wp.id) return;
    _handedOff = true;
    _presenceSub?.cancel();
    widget.onPeerSelected(wp, transport);
  }

  Widget _buildInviteUi(ThemeData theme) {
    final inviter = _inviteFrom;
    if (inviter == null) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('${inviter.alias} 邀请你对战',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _acceptInvite,
                  icon: const Icon(Icons.check),
                  label: const Text('接受'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _inviteFrom = null),
                  icon: const Icon(Icons.close),
                  label: const Text('拒绝'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingUi(ThemeData theme) {
    final peer = _waitingPeer;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text('等待对方确认...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 8),
            if (peer != null)
              Text('对端: ${peer.alias}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                _transport?.leaveScope(_sessionScope ?? '');
                setState(() {
                  _waitingForPeer = false;
                  _waitingPeer = null;
                  _sessionScope = null;
                });
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // 别人邀请我
    if (_inviteFrom != null) return _buildInviteUi(theme);

    // 已邀请对方，等待接受
    if (_waitingForPeer) return _buildWaitingUi(theme);

    if (!_scanning) {
      // 初始状态：显示扫描按钮
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_find, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('搜索同一 WiFi 下的其他设备',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.search),
                label: const Text('扫描局域网设备'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 扫描中
    return Column(
      children: [
        // 状态栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Text('扫描中...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_peers.length} 台设备',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ],
          ),
        ),

        // 设备列表
        Expanded(
          child: _peers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('暂无设备\n\niOS 设备需在前台运行本 App',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        )),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  itemCount: _peers.length,
                  itemBuilder: (_, i) {
                    final p = _peers.values.elementAt(i);
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(Icons.phone_android,
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                        title: Text(p.alias, style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                        subtitle: Text(p.address, style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        )),
                        trailing: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.chevron_right, size: 18,
                              color: theme.colorScheme.primary),
                        ),
                        onTap: () => _sendInvite(p),
                      ),
                    );
                  },
                ),
        ),

        // 底部操作
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _stopScan,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('停止扫描'),
            ),
          ),
        ),
      ],
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
  final _portCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final alias = await _LanPrefs.getAlias();
    final port = await _LanPrefs.getMulticastPort();
    final addr = await _LanPrefs.getMulticastAddress();
    if (!mounted) return;
    setState(() {
      _aliasCtrl.text = alias;
      _portCtrl.text = port.toString();
      _addrCtrl.text = addr;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _portCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _LanPrefs.setAlias(_aliasCtrl.text.trim());
    final port = int.tryParse(_portCtrl.text.trim()) ?? widget.multicastPort;
    await _LanPrefs.setMulticastPort(port);
    final addr = _addrCtrl.text.trim().isEmpty ? widget.multicastAddress : _addrCtrl.text.trim();
    await _LanPrefs.setMulticastAddress(addr);
    if (!mounted) return;
    widget.onSaved?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 设备身份
        Text('设备身份', style: theme.textTheme.titleMedium),
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

        // 网络参数
        Text('网络参数', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _portCtrl,
                  decoration: const InputDecoration(
                    labelText: '多播端口',
                    prefixIcon: Icon(Icons.wifi),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addrCtrl,
                  decoration: const InputDecoration(
                    labelText: '多播地址',
                    prefixIcon: Icon(Icons.router),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                Text('修改端口/地址后需要重新扫描才能生效。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    )),
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
