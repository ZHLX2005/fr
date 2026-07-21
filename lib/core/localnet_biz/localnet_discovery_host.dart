/// LocalNet biz 入口页面 — 直接使用 localnet 的 widget
///
/// 业务层不自己维护发现/连接/UI，全部委托：
/// - 选 LAN：`LanDiscovery().buildPage(...)` → 拿到 peer + transport
/// - 选 Relay：`RelayDiscovery().buildPage(...)` → 拿到 room code + transport
/// - 拿到 transport 后传给 localnetService.attach()，订阅 events 驱动 UI
import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'localnet_service.dart';
import 'models/localnet_config.dart';
import 'pages/localnet_chat_page.dart';
import 'pages/localnet_debug_page.dart';
import 'pages/localnet_settings_page.dart';

/// biz 入口页面 — 直接渲染 localnet widget
class LocalnetBizHostPage extends StatefulWidget {
  const LocalnetBizHostPage({super.key});

  @override
  State<LocalnetBizHostPage> createState() => _LocalnetBizHostPageState();
}

class _LocalnetBizHostPageState extends State<LocalnetBizHostPage> {
  MessageNetMode _mode = MessageNetMode.lan;
  fw.Transport? _transport;
  String? _scope;
  String? _error;

  /// 选模式
  void _switchMode(MessageNetMode mode) {
    setState(() {
      _mode = mode;
      _transport = null;
      _scope = null;
      _error = null;
    });
  }

  /// localnet widget 触发连接成功
  void _onConnected(fw.Transport transport, fw.DiscoveredPeer peer) {
    final scope = 'chat-${peer.id}';
    setState(() {
      _transport = transport;
      _scope = scope;
      _error = null;
    });
    localnetService.attach(transport, scope);
  }

  /// localnet widget 触发错误
  void _onError(String error) {
    setState(() => _error = error);
  }

  /// 断开
  Future<void> _disconnect() async {
    await _transport?.stop();
    setState(() {
      _transport = null;
      _scope = null;
    });
    localnetService.detach();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MessageNet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocalnetSettingsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocalnetDebugPage()),
            ),
          ),
        ],
      ),
      body: _transport == null
          ? _buildDiscoveryView()
          : _buildChatView(),
    );
  }

  /// 未连接：渲染 localnet 的发现 widget
  Widget _buildDiscoveryView() {
    return Column(
      children: [
        _buildModeSwitcher(),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _mode == MessageNetMode.lan
                  ? fw.LanDiscovery().buildPage(
                      onPeerSelected: (peer) async {
                        // 自动建立 transport（业务层零连接代码）
                        final transport = await fw.LanTransport.create();
                        await transport.joinScope('chat-${peer.id}');
                        _onConnected(transport, peer);
                      },
                      onError: _onError,
                    )
                  : fw.RelayDiscovery(
                      relayUrl: 'http://47.110.80.47:8988',
                    ).buildPage(
                      onPeerSelected: (peer) async {
                        // Relay widget 内部已经 createRoom/joinRoom
                        // 只需从 widget 获取 transport（简化：业务层持有 transport）
                        _onError('Relay: 通过 widget 内 transport 完成，请检查 widget 实现');
                      },
                      onError: _onError,
                    ),
        ),
      ],
    );
  }

  /// 已连接：进入聊天
  Widget _buildChatView() {
    return Column(
      children: [
        _buildConnectionBar(),
        Expanded(child: LocalnetChatPage(scope: _scope!)),
      ],
    );
  }

  Widget _buildConnectionBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('已连接 · scope: $_scope')),
          TextButton(
            onPressed: _disconnect,
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SegmentedButton<MessageNetMode>(
        segments: const [
          ButtonSegment(
            value: MessageNetMode.lan,
            icon: Icon(Icons.wifi),
            label: Text('局域网'),
          ),
          ButtonSegment(
            value: MessageNetMode.relay,
            icon: Icon(Icons.cloud),
            label: Text('跨网络'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => _switchMode(s.first),
      ),
    );
  }
}