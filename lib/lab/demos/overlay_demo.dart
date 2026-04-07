import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/overlay/overlay_service.dart';

/// 悬浮窗截屏Demo
class OverlayDemo extends DemoPage {
  @override
  String get title => '悬浮截屏';

  @override
  String get description => 'Android悬浮窗权限与截屏功能演示';

  @override
  bool get preferFullScreen => false;

  @override
  Widget buildPage(BuildContext context) {
    return const OverlayDemoPage();
  }
}

class OverlayDemoPage extends StatefulWidget {
  const OverlayDemoPage({super.key});

  @override
  State<OverlayDemoPage> createState() => _OverlayDemoPageState();
}

class _OverlayDemoPageState extends State<OverlayDemoPage> {
  final OverlayService _overlayService = OverlayService();
  bool _hasPermission = false;
  bool _isOverlayActive = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _overlayService.checkOverlayPermission();
    setState(() {
      _hasPermission = hasPermission;
    });
  }

  Future<void> _requestPermission() async {
    final granted = await _overlayService.requestOverlayPermission();
    setState(() {
      _hasPermission = granted;
    });
    if (granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('悬浮窗权限已授予')),
        );
      }
    }
  }

  Future<void> _toggleOverlay() async {
    if (!_overlayService.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('悬浮窗仅支持Android设备')),
      );
      return;
    }

    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先授予悬浮窗权限')),
      );
      return;
    }

    await _overlayService.toggleOverlay(
      onScreenshot: () {
        debugPrint('Screenshot requested');
      },
    );

    setState(() {
      _isOverlayActive = _overlayService.isOverlayActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('悬浮截屏演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '悬浮窗权限状态',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _hasPermission
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: _hasPermission
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hasPermission ? '已授权' : '未授权',
                          style: TextStyle(
                            color: _hasPermission
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_hasPermission)
                      ElevatedButton(
                        onPressed: _requestPermission,
                        child: const Text('请求悬浮窗权限'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '悬浮窗控制',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _isOverlayActive
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: _isOverlayActive
                              ? Colors.blue
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isOverlayActive ? '已显示' : '已隐藏',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _toggleOverlay,
                      child: Text(
                        _isOverlayActive ? '隐藏悬浮窗' : '显示悬浮窗',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '说明',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '此功能仅在Android设备上有效。需要悬浮窗权限才能显示悬浮按钮。'
                      '悬浮按钮可拖动到任意位置，点击后执行截屏操作。',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void registerOverlayDemo() {
  demoRegistry.register(OverlayDemo());
}