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
    _initService();
  }

  Future<void> _initService() async {
    await _overlayService.init();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _overlayService.checkOverlayPermission();
    setState(() {
      _hasPermission = hasPermission;
    });
  }

  Future<void> _requestPermission() async {
    // 跳转到悬浮窗权限设置页面
    await _overlayService.requestOverlayPermission();
    // 等待用户返回后检查权限状态
    await Future.delayed(const Duration(milliseconds: 500));
    await _checkPermission();
  }

  Future<void> _toggleOverlay() async {
    if (!_overlayService.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('悬浮窗仅支持Android设备')),
      );
      return;
    }

    // 先检查权限
    await _checkPermission();
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先授予悬浮窗权限')),
      );
      return;
    }

    final success = await _overlayService.showOverlayButton();

    setState(() {
      _isOverlayActive = _overlayService.isOverlayActive;
    });

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('启动悬浮窗失败，请检查权限设置')),
      );
    }
  }

  Future<void> _hideOverlay() async {
    await _overlayService.hideOverlayButton();
    setState(() {
      _isOverlayActive = false;
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
                        child: const Text('前往授权悬浮窗权限'),
                      ),
                    if (_hasPermission)
                      ElevatedButton(
                        onPressed: _checkPermission,
                        child: const Text('刷新权限状态'),
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
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _hasPermission ? _toggleOverlay : null,
                          child: const Text('显示悬浮窗'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isOverlayActive ? _hideOverlay : null,
                          child: const Text('隐藏悬浮窗'),
                        ),
                      ],
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
                      '1. 悬浮窗权限需要在系统设置中手动开启\n'
                      '2. 点击"显示悬浮窗"后，屏幕上会出现一个悬浮按钮\n'
                      '3. 拖动悬浮按钮可调整位置\n'
                      '4. 点击悬浮按钮可进行截屏\n'
                      '5. 截屏图片保存在应用私有目录',
                      style: TextStyle(fontSize: 14),
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

/// 注册悬浮窗Demo
void registerOverlayDemo() {
  demoRegistry.register(OverlayDemo());
}