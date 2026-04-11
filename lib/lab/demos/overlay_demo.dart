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

  // AI 配置
  String _apiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  String _apiKey = '';
  String _selectedModel = 'glm-4v-flash';
  String _systemPrompt = '你是一个专业的AI助手，请根据图片回答用户问题。';

  final List<String> _availableModels = [
    'glm-4v-flash',
    'glm-5v-turbo',
    'glm-4.6v',
  ];

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
    // 回填已保存的配置到表单
    _loadConfigToForm();
  }

  void _loadConfigToForm() {
    final config = _overlayService.aiConfig;
    setState(() {
      _apiUrl = config['apiUrl'] ?? _apiUrl;
      _apiKey = config['apiKey'] ?? _apiKey;
      _selectedModel = config['model'] ?? _selectedModel;
      _systemPrompt = config['systemPrompt'] ?? _systemPrompt;
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

  Future<void> _saveConfig() async {
    await _overlayService.saveAiConfig(
      apiUrl: _apiUrl,
      apiKey: _apiKey,
      model: _selectedModel,
      systemPrompt: _systemPrompt,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('悬浮截屏演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
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
                          onPressed: (_hasPermission && _apiKey.isNotEmpty) ? _toggleOverlay : null,
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
                      'AI 配置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(labelText: 'API URL', hintText: 'https://...'),
                      controller: TextEditingController(text: _apiUrl),
                      onChanged: (v) => _apiUrl = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(labelText: 'API Key', hintText: 'your-api-key'),
                      controller: TextEditingController(text: _apiKey),
                      onChanged: (v) => _apiKey = v,
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedModel,
                      decoration: const InputDecoration(labelText: '模型'),
                      items: _availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (v) => setState(() => _selectedModel = v!),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(labelText: '系统提示词'),
                      controller: TextEditingController(text: _systemPrompt),
                      onChanged: (v) => _systemPrompt = v,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _saveConfig,
                      child: const Text('保存配置'),
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
                      '4. 点击悬浮按钮可进行区域截屏\n'
                      '5. 截屏后可输入问题，AI 将流式回答',
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