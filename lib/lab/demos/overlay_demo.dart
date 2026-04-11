import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../native/overlay/overlay_service.dart';

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
  bool _isPreviewShowing = false;
  Uint8List? _currentScreenshot;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _overlayService.init();
    await _checkPermission();
    // 从原生层检查悬浮窗实际状态，避免退出后状态丢失
    await _checkOverlayStatus();
    _overlayService.setOnRegionCaptured((data) {
      if (mounted && data != null) {
        setState(() {
          _currentScreenshot = data;
          _isPreviewShowing = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showPreviewSheet();
        });
      }
    });
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _overlayService.checkOverlayPermission();
    setState(() {
      _hasPermission = hasPermission;
    });
  }

  Future<void> _checkOverlayStatus() async {
    final isShowing = await _overlayService.isFloatingShowing();
    setState(() {
      _isOverlayActive = isShowing;
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

  void _showPreviewSheet() {
    if (!_isPreviewShowing || _currentScreenshot == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ScreenshotPreviewSheet(
        imageData: _currentScreenshot!,
        onSave: () {
          Navigator.pop(ctx);
          _saveScreenshot();
        },
        onReselect: () {
          Navigator.pop(ctx);
          _reselectRegion();
        },
      ),
    );
  }

  Future<void> _saveScreenshot() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('截图已保存到图库')),
    );
    _overlayService.clearPendingScreenshot();
    setState(() {
      _isPreviewShowing = false;
      _currentScreenshot = null;
    });
  }

  void _reselectRegion() {
    _overlayService.clearPendingScreenshot();
    setState(() {
      _isPreviewShowing = false;
      _currentScreenshot = null;
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
                      '5. 截屏后可在图库中查看',
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

class _ScreenshotPreviewSheet extends StatelessWidget {
  final Uint8List imageData;
  final VoidCallback onSave;
  final VoidCallback onReselect;

  const _ScreenshotPreviewSheet({
    required this.imageData,
    required this.onSave,
    required this.onReselect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                imageData,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: onReselect,
                icon: const Icon(Icons.refresh),
                label: const Text('重新截取'),
              ),
              ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save),
                label: const Text('保存'),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// 注册悬浮窗Demo
void registerOverlayDemo() {
  demoRegistry.register(OverlayDemo());
}