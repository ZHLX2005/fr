import 'package:flutter/material.dart';

import '../localnet_service.dart';
import '../models/localnet_device.dart';
import 'localnet_chat_page.dart';
import 'localnet_debug_page.dart';
import 'localnet_settings_page.dart';

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
    setState(() => _isStarting = true);
    await _service.start();
    setState(() => _isStarting = false);
  }

  @override
  void dispose() {
    // Don't stop service on dispose - keep it running
    super.dispose();
  }

  void _navigateToChat(LocalnetDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalnetChatPage(device: device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalNet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocalnetSettingsPage()),
              );
            },
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocalnetDebugPage()),
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
          // 本机信息卡片
          _buildSelfCard(),
          const Divider(height: 1),
          // 设备列表
          Expanded(
            child: _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                  '本机 · 在线',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green,
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
                  '确保其他设备也运行了 LocalNet',
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
