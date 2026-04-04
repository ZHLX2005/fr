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
  late bool _httpEnabled;
  late bool _multicastEnabled;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final config = configService.config;
    _aliasController = TextEditingController(text: config.deviceAlias);
    _portController = TextEditingController(text: config.port.toString());
    _httpEnabled = config.httpEnabled;
    _multicastEnabled = config.multicastEnabled;

    _aliasController.addListener(_onChanged);
    _portController.addListener(_onChanged);
  }

  void _onChanged() {
    final config = configService.config;
    final newAlias = _aliasController.text;
    final newPort = int.tryParse(_portController.text) ?? config.port;
    final newHttp = _httpEnabled;
    final newMulticast = _multicastEnabled;

    setState(() {
      _hasChanges = newAlias != config.deviceAlias ||
          newPort != config.port ||
          newHttp != config.httpEnabled ||
          newMulticast != config.multicastEnabled;
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
      httpEnabled: _httpEnabled,
      multicastEnabled: _multicastEnabled,
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
      _httpEnabled = config.httpEnabled;
      _multicastEnabled = config.multicastEnabled;
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
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('HTTP 服务器'),
                  subtitle: Text(
                    _httpEnabled
                        ? '启用 HTTP 服务器，接收 Register 请求'
                        : '禁用后将无法被其他设备发现',
                  ),
                  value: _httpEnabled,
                  onChanged: (value) {
                    setState(() {
                      _httpEnabled = value;
                      _onChanged();
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('UDP 多播发现'),
                  subtitle: Text(
                    _multicastEnabled
                        ? '启用 UDP 多播广播和监听'
                        : '禁用后将仅依赖 HTTP 扫描发现',
                  ),
                  value: _multicastEnabled,
                  onChanged: (value) {
                    setState(() {
                      _multicastEnabled = value;
                      _onChanged();
                    });
                  },
                ),
              ],
            ),
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
                    '• HTTP 服务器：必须启用才能响应其他设备的发现请求',
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• UDP 多播：广播自己的存在，禁用后只能被发现而不能主动发现别人',
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
