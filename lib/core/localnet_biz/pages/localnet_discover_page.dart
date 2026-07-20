import 'package:flutter/material.dart';

import '../localnet_service.dart';
import '../models/localnet_config.dart';
import '../models/localnet_device.dart';
import 'localnet_chat_page.dart';
import 'localnet_debug_page.dart';
import 'localnet_settings_page.dart';

/// MessageNet 主页面 — 设备发现 + 模式切换（LAN / Relay）
///
/// - LAN 模式：UDP 多播发现，被动等设备上线，列表里展示同子网设备
/// - Relay 模式：跨网络，需要房间号才能发现对端；host 创建房间后把房间号给 guest
class LocalnetDiscoverPage extends StatefulWidget {
  const LocalnetDiscoverPage({super.key});

  @override
  State<LocalnetDiscoverPage> createState() => _LocalnetDiscoverPageState();
}

class _LocalnetDiscoverPageState extends State<LocalnetDiscoverPage> {
  final _service = localnetService;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _startService();
  }

  Future<void> _startService() async {
    if (_isStarting) return;
    if (_service.isReady) return;
    setState(() => _isStarting = true);
    try {
      await _service.start();
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  void dispose() {
    // 退出 demo（页面从路由树移除）时自动停止服务
    _service.stop();
    super.dispose();
  }

  void _navigateToChat(LocalnetDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LocalnetChatPage(device: device)),
    );
  }

  /// 切换模式 — 自动重启服务应用新 transportKind
  Future<void> _switchMode(MessageNetMode newMode) async {
    final cfg = _service.config.config;
    if (cfg.mode == newMode) return;
    final newCfg = cfg.copyWith(mode: newMode);
    await _service.updateConfig(newCfg);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mode = _service.config.config.mode;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MessageNet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LocalnetSettingsPage(),
                ),
              );
            },
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LocalnetDebugPage(),
                ),
              );
            },
            tooltip: '调试日志',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startService,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 模式切换条
          _buildModeSwitcher(mode),
          // 本机信息卡片
          _buildSelfCard(mode),
          const Divider(height: 1),
          // 设备列表 / 房间发现区
          Expanded(
            child:
                mode == MessageNetMode.relay
                    ? _buildRelayPanel()
                    : _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  /// 模式切换条（LAN / Relay）
  Widget _buildModeSwitcher(MessageNetMode current) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SegmentedButton<MessageNetMode>(
        segments: const [
          ButtonSegment(
            value: MessageNetMode.lan,
            icon: Icon(Icons.wifi, size: 18),
            label: Text('局域网'),
          ),
          ButtonSegment(
            value: MessageNetMode.relay,
            icon: Icon(Icons.cloud, size: 18),
            label: Text('跨网络'),
          ),
        ],
        selected: {current},
        onSelectionChanged: (selection) => _switchMode(selection.first),
      ),
    );
  }

  Widget _buildSelfCard(MessageNetMode mode) {
    final cfg = _service.config.config;
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(
            Icons.smartphone,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _service.deviceAlias,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '本机 · ${mode == MessageNetMode.relay ? "Relay" : "LAN"} · 在线',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
                ),
                if (mode == MessageNetMode.relay)
                  Text(
                    '中继: ${cfg.relayUrl}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  )
                else if (_service.myIp != null)
                  Text(
                    '${_service.myIp}:${cfg.port}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          if (_isStarting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  /// LAN 模式：被动设备发现列表
  Widget _buildDeviceList() {
    return StreamBuilder<List<LocalnetDevice>>(
      stream: _service.devicesStream,
      initialData: _service.devices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];

        if (devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_find,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '正在搜索设备...',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '确保其他设备也运行了 MessageNet (LAN)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return _DeviceTile(
              device: device,
              onTap: () => _navigateToChat(device),
            );
          },
        );
      },
    );
  }

  /// Relay 模式：房间号发现 + 创建房间面板
  Widget _buildRelayPanel() {
    return _RelayPanel();
  }
}

/// Relay 模式面板 — 创建/加入/离开房间
class _RelayPanel extends StatefulWidget {
  const _RelayPanel();

  @override
  State<_RelayPanel> createState() => _RelayPanelState();
}

class _RelayPanelState extends State<_RelayPanel> {
  final _service = localnetService;
  final _roomCodeController = TextEditingController();
  bool _isBusy = false;
  String? _error;

  bool get _inRoom => _service.currentRoomCode != null;

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await _service.createRelayRoom();
      if (mounted) {
        setState(() => _isBusy = false);
        _autoNavigate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = '创建房间失败: $e';
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位房间号');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await _service.joinRelayRoom(code);
      if (mounted) {
        setState(() => _isBusy = false);
        _autoNavigate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = '加入房间失败: $e';
        });
      }
    }
  }

  void _autoNavigate() {
    final bucketId = _service.relayBucketId;
    if (bucketId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RelayChatPage(
            peerId: bucketId,
            peerAlias: '对方',
          ),
        ),
      );
    }
  }

  Future<void> _leaveRoom() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await _service.leaveRelayRoom();
    } catch (_) {}
    if (mounted) setState(() => _isBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_inRoom) return _buildRoomPanel();
    return _buildLobbyPanel();
  }

  /// 未加入房间 — 创建 / 加入
  Widget _buildLobbyPanel() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            '跨网络消息通讯',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '通过中继服务器 ${_service.config.config.relayUrl}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 32),

          // 创建房间
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _createRoom,
              icon: _isBusy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline),
              label: Text(_isBusy ? '创建中...' : '创建房间'),
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('或'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),

          // 输入房间号
          TextField(
            controller: _roomCodeController,
            decoration: InputDecoration(
              hintText: '输入 6 位房间号',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key),
              suffixText: '房间号',
              suffixStyle: TextStyle(
                color: theme.colorScheme.outline,
                fontSize: 12,
              ),
            ),
            maxLength: 6,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _joinRoom(),
          ),

          const SizedBox(height: 12),

          // 加入房间
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isBusy ? null : _joinRoom,
              icon: _isBusy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_isBusy ? '加入中...' : '加入房间'),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// 已加入房间 — 显示房间信息 + 离开
  Widget _buildRoomPanel() {
    final theme = Theme.of(context);
    final roomCode = _service.currentRoomCode;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('已加入房间', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      roomCode ?? '',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '已连接中继服务器',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isBusy ? null : _leaveRoom,
              icon: _isBusy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: Text(_isBusy ? '离开中...' : '离开房间'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final LocalnetDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  IconData get _icon {
    switch (device.deviceType) {
      case DeviceType.mobile:
        return Icons.phone_android;
      case DeviceType.web:
        return Icons.web;
      case DeviceType.desktop:
        return Icons.computer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon, size: 32),
      title: Text(device.alias),
      subtitle: Text('${device.ip}:${device.port}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}