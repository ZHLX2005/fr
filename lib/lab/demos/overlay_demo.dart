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
  bool get preferFullScreen => true;

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
    await _checkOverlayStatus();
    _loadConfigToForm();
  }

  Future<void> _loadConfigToForm() async {
    final config = await _overlayService.loadAiConfig();
    if (mounted) {
      setState(() {
        _apiUrl = config['apiUrl'] ?? _apiUrl;
        _apiKey = config['apiKey'] ?? _apiKey;
        _selectedModel = config['model'] ?? _selectedModel;
        _systemPrompt = config['systemPrompt'] ?? _systemPrompt;
      });
    }
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _overlayService.checkOverlayPermission();
    if (mounted) {
      setState(() {
        _hasPermission = hasPermission;
      });
    }
  }

  Future<void> _checkOverlayStatus() async {
    final isShowing = await _overlayService.isFloatingShowing();
    if (mounted) {
      setState(() {
        _isOverlayActive = isShowing;
      });
    }
  }

  Future<void> _requestPermission() async {
    await _overlayService.requestOverlayPermission();
    await Future.delayed(const Duration(milliseconds: 500));
    await _checkPermission();
  }

  Future<void> _toggleOverlay() async {
    if (!_overlayService.isSupported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('悬浮窗仅支持Android设备')));
      return;
    }

    if (!_hasPermission) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先授予悬浮窗权限')));
      return;
    }

    final success = await _overlayService.showOverlayButton();

    if (mounted) {
      setState(() {
        _isOverlayActive = _overlayService.isOverlayActive;
      });
    }

    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启动悬浮窗失败，请检查权限设置')));
    }
  }

  Future<void> _hideOverlay() async {
    await _overlayService.hideOverlayButton();
    if (mounted) {
      setState(() {
        _isOverlayActive = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    await _overlayService.saveAiConfig(
      apiUrl: _apiUrl,
      apiKey: _apiKey,
      model: _selectedModel,
      systemPrompt: _systemPrompt,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置已保存')));
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
            _buildPermissionCard(),
            const SizedBox(height: 16),
            _buildOverlayControlCard(),
            const SizedBox(height: 16),
            _buildAiConfigCard(),
            const SizedBox(height: 16),
            _buildInstructionCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '悬浮窗权限',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _hasPermission ? Icons.check_circle : Icons.cancel,
                  color: _hasPermission ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _hasPermission ? '已授权' : '未授权',
                  style: TextStyle(
                    color: _hasPermission ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_hasPermission)
              ElevatedButton(
                onPressed: _requestPermission,
                child: const Text('前往授权'),
              ),
            if (_hasPermission)
              OutlinedButton(
                onPressed: _checkPermission,
                child: const Text('刷新状态'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '悬浮窗控制',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _isOverlayActive ? Icons.visibility : Icons.visibility_off,
                  color: _isOverlayActive ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isOverlayActive ? '运行中' : '已停止',
                  style: TextStyle(
                    color: _isOverlayActive ? Colors.blue : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_hasPermission && _apiKey.isNotEmpty)
                        ? _toggleOverlay
                        : null,
                    child: const Text('显示悬浮窗'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isOverlayActive ? _hideOverlay : null,
                    child: const Text('隐藏悬浮窗'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI 配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '输入 API Key',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _apiKey),
              onChanged: (v) => _apiKey = v,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'API URL',
                hintText: '输入 API URL',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _apiUrl),
              onChanged: (v) => _apiUrl = v,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedModel,
              decoration: const InputDecoration(
                labelText: '模型',
                border: OutlineInputBorder(),
              ),
              items: _availableModels
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedModel = v);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: '系统提示词',
                hintText: '自定义 AI 行为指令',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _systemPrompt),
              onChanged: (v) => _systemPrompt = v,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveConfig,
                child: const Text('保存配置'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '使用说明',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. 授权悬浮窗权限\n'
              '2. 配置 API Key 并保存\n'
              '3. 点击"显示悬浮窗"启动悬浮按钮\n'
              '4. 点击悬浮按钮选择截屏区域\n'
              '5. AI 自动识别并回答',
              style: TextStyle(fontSize: 14, height: 1.5),
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
