import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';

/// 音量衰减 Demo
/// 使用 Android 系统音量控制实现全局音量衰减控制
/// 支持 App Shortcuts 长按快捷启动
class VolumeDecayDemo extends DemoPage {
  @override
  String get title => '音量衰减';

  @override
  String get description => '控制全局媒体音量衰减，类似音量君';

  @override
  Widget buildPage(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Center(
        child: Text('仅支持 Android 设备'),
      );
    }
    return const _VolumeDecayPage();
  }
}

class _VolumeDecayPage extends StatefulWidget {
  const _VolumeDecayPage();

  @override
  State<_VolumeDecayPage> createState() => _VolumeDecayPageState();
}

class _VolumeDecayPageState extends State<_VolumeDecayPage> {
  static const _channel = MethodChannel('io.github.xiaodouzi.fr/volume');

  int _currentGain = 40;
  int _maxVolume = 15;
  int _savedVolume = -1;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final gain = await _channel.invokeMethod<int>('getGain') ?? 40;
      final maxVol = await _channel.invokeMethod<int>('getMaxVolume') ?? 15;
      final running = await _channel.invokeMethod<bool>('isRunning') ?? false;
      setState(() {
        _currentGain = gain;
        _maxVolume = maxVol;
        _isRunning = running;
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to load state: ${e.message}');
    }
  }

  Future<void> _turnOn() async {
    try {
      await _channel.invokeMethod('turnOn', {'gain': _currentGain});
      setState(() => _isRunning = true);
    } on PlatformException catch (e) {
      debugPrint('Failed to turn on: ${e.message}');
    }
  }

  Future<void> _turnOff() async {
    try {
      await _channel.invokeMethod('turnOff');
      setState(() => _isRunning = false);
    } on PlatformException catch (e) {
      debugPrint('Failed to turn off: ${e.message}');
    }
  }

  Future<void> _setGain(int gain) async {
    setState(() => _currentGain = gain);
    try {
      if (_isRunning) {
        await _channel.invokeMethod('setGain', {'gain': gain});
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to set gain: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _isRunning ? Icons.volume_off : Icons.volume_up,
                    size: 32,
                    color: _isRunning ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isRunning ? '响度衰减已开启' : '响度衰减已关闭',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '当前增益: $_currentGain%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 增益滑块
          Text(
            '衰减增益: $_currentGain%',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('10%'),
              Expanded(
                child: Slider(
                  value: _currentGain.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 9,
                  label: '$_currentGain%',
                  onChanged: (value) => _setGain(value.round()),
                ),
              ),
              const Text('100%'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '建议设置为 30%-50%，可大幅降低短视频响度',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 24),

          // 快捷预设
          Text(
            '快捷预设',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: '轻柔 (30%)',
                selected: _currentGain == 30,
                onTap: () => _setGain(30),
              ),
              _PresetChip(
                label: '舒适 (40%)',
                selected: _currentGain == 40,
                onTap: () => _setGain(40),
              ),
              _PresetChip(
                label: '均衡 (50%)',
                selected: _currentGain == 50,
                onTap: () => _setGain(50),
              ),
              _PresetChip(
                label: '正常 (70%)',
                selected: _currentGain == 70,
                onTap: () => _setGain(70),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 开关按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isRunning ? _turnOff : _turnOn,
              icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(_isRunning ? '关闭响度衰减' : '开启响度衰减'),
              style: FilledButton.styleFrom(
                backgroundColor: _isRunning ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 说明
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '使用说明',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• 长按桌面图标可快速开启/关闭衰减\n'
                    '• 衰减开启后，系统音量会被等比压缩\n'
                    '• 关闭后会自动恢复原始音量\n'
                    '• 推荐配合系统音量 1-2 格使用',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      backgroundColor: selected ? Colors.green.shade100 : null,
      side: BorderSide(
        color: selected ? Colors.green : Colors.grey.shade300,
      ),
      onPressed: onTap,
    );
  }
}

void registerVolumeDecayDemo() {
  demoRegistry.register(VolumeDecayDemo());
}
