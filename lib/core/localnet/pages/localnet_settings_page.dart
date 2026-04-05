import 'package:flutter/material.dart';

import '../localnet_service.dart';
import '../models/localnet_config.dart';
import '../services/config_service.dart';

class LocalnetSettingsPage extends StatefulWidget {
  const LocalnetSettingsPage({super.key});

  @override
  State<LocalnetSettingsPage> createState() => _LocalnetSettingsPageState();
}

class _LocalnetSettingsPageState extends State<LocalnetSettingsPage> {
  late TextEditingController _aliasController;
  late TextEditingController _portController;
  late bool _udpBroadcastEnabled;
  late bool _udpListenerEnabled;
  late bool _httpServerEnabled;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final config = configService.config;
    _aliasController = TextEditingController(text: config.deviceAlias);
    _portController = TextEditingController(text: config.port.toString());
    _udpBroadcastEnabled = config.udpBroadcastEnabled;
    _udpListenerEnabled = config.udpListenerEnabled;
    _httpServerEnabled = config.httpServerEnabled;

    _aliasController.addListener(_onChanged);
    _portController.addListener(_onChanged);
  }

  void _onChanged() {
    final config = configService.config;
    final newAlias = _aliasController.text;
    final newPort = int.tryParse(_portController.text) ?? config.port;

    setState(() {
      _hasChanges = newAlias != config.deviceAlias ||
          newPort != config.port ||
          _udpBroadcastEnabled != config.udpBroadcastEnabled ||
          _udpListenerEnabled != config.udpListenerEnabled ||
          _httpServerEnabled != config.httpServerEnabled;
    });
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newConfig = LocalnetConfig(
      deviceAlias: _aliasController.text.trim().isEmpty
          ? 'Flutter Device'
          : _aliasController.text.trim(),
      udpBroadcastEnabled: _udpBroadcastEnabled,
      udpListenerEnabled: _udpListenerEnabled,
      httpServerEnabled: _httpServerEnabled,
      port: int.tryParse(_portController.text) ?? 53317,
    );

    await localnetService.updateConfig(newConfig);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存，服务已重启'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _reset() async {
    await configService.reset();
    final config = configService.config;

    setState(() {
      _aliasController.text = config.deviceAlias;
      _portController.text = config.port.toString();
      _udpBroadcastEnabled = config.udpBroadcastEnabled;
      _udpListenerEnabled = config.udpListenerEnabled;
      _httpServerEnabled = config.httpServerEnabled;
      _hasChanges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalNet 设置'),
        actions: [
          TextButton(
            onPressed: _hasChanges ? _save : null,
            child: Text(
              '保存',
              style: TextStyle(
                color: _hasChanges ? null : Colors.grey,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 状态信息
          _buildStatusCard(),
          const SizedBox(height: 24),

          // 基本设置
          Text(
            '基本设置',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _aliasController,
                    decoration: const InputDecoration(
                      labelText: '设备名称',
                      hintText: '输入设备显示名称',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '53317',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 服务开关
          Text(
            '服务开关',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          // UDP 广播开关
          _buildComponentSwitchCard(
            title: 'UDP 广播',
            icon: Icons.upload,
            enabled: _udpBroadcastEnabled,
            port: '53317',
            detail: '多播: 224.0.0.167',
            warning: '每3秒广播一次（电池消耗较高）',
            onChanged: (value) {
              setState(() {
                _udpBroadcastEnabled = value;
                _onChanged();
              });
            },
          ),
          const SizedBox(height: 8),

          // UDP 监听开关
          _buildComponentSwitchCard(
            title: 'UDP 监听',
            icon: Icons.download,
            enabled: _udpListenerEnabled,
            port: '53317',
            detail: null,
            warning: null,
            onChanged: (value) {
              setState(() {
                _udpListenerEnabled = value;
                _onChanged();
              });
            },
          ),
          const SizedBox(height: 8),

          // HTTP 服务开关
          _buildComponentSwitchCard(
            title: 'HTTP 服务',
            icon: Icons.http,
            enabled: _httpServerEnabled,
            port: '53317',
            detail: null,
            warning: null,
            onChanged: (value) {
              setState(() {
                _httpServerEnabled = value;
                _onChanged();
              });
            },
          ),

          const SizedBox(height: 24),

          // 重置
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restore),
            label: const Text('重置为默认'),
          ),

          const SizedBox(height: 32),

          // 说明
          Text(
            '说明',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• UDP 广播：主动发送 UDP 多播包，每3秒一次（电池消耗较高）',
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• UDP 监听：接收其他设备的 UDP 多播包',
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• HTTP 服务：响应 /join 等 HTTP 请求，必开',
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• 修改设置后服务会自动重启以应用更改',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentSwitchCard({
    required String title,
    required IconData icon,
    required bool enabled,
    required String port,
    String? detail,
    String? warning,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '端口: $port${detail != null ? '  |  $detail' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (warning != null)
                    Text(
                      warning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange,
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final service = localnetService;
    final cfg = configService.config;

    Color stateColor;
    String stateText;
    switch (service.serviceState) {
      case 'RUNNING':
        stateColor = Colors.green;
        stateText = '运行中';
        break;
      case 'STARTING':
        stateColor = Colors.orange;
        stateText = '启动中';
        break;
      case 'ERROR':
        stateColor = Colors.red;
        stateText = '错误';
        break;
      default:
        stateColor = Colors.grey;
        stateText = '已停止';
    }

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '当前状态',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text('服务状态: $stateText'),
              ],
            ),
            const SizedBox(height: 8),
            Text('设备 ID: ${cfg.deviceAlias}'),
            Text('设备指纹: ...'), // 敏感信息可以隐藏
            Text('发现设备数: ${service.devices.length}'),
          ],
        ),
      ),
    );
  }
}
