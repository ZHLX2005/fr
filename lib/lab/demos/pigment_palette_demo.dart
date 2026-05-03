import 'package:flutter/material.dart';

import '../../native/overlay/pigment_overlay_service.dart';
import '../lab_container.dart';

class PigmentPaletteDemo extends DemoPage {
  @override
  String get title => 'Pigment 调色板';

  @override
  String get description => 'Flutter 只负责控制区；悬浮气泡、面板、取色和画布都由 Kotlin 原生实现。';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const PigmentPaletteDemoPage();
  }
}

void registerPigmentPaletteDemo() {
  demoRegistry.register(PigmentPaletteDemo());
}

class PigmentPaletteDemoPage extends StatefulWidget {
  const PigmentPaletteDemoPage({super.key});

  @override
  State<PigmentPaletteDemoPage> createState() => _PigmentPaletteDemoPageState();
}

class _PigmentPaletteDemoPageState extends State<PigmentPaletteDemoPage>
    with WidgetsBindingObserver {
  final PigmentOverlayService _service = PigmentOverlayService();
  bool _hasPermission = false;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _init() async {
    await _service.init();
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final hasPermission = await _service.checkOverlayPermission();
    final isActive = await _service.isShowing();
    if (!mounted) return;
    setState(() {
      _hasPermission = hasPermission;
      _isActive = isActive;
    });
  }

  Future<void> _requestPermission() async {
    await _service.requestOverlayPermission();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _start() async {
    final success = await _service.start();
    await _refreshStatus();
    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启动失败，请先确认悬浮窗权限')));
    }
  }

  Future<void> _stop() async {
    await _service.stop();
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pigment 原生悬浮窗')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: '实现方式',
            body:
                '按照你的要求，这个 demo 不在 Flutter 里模拟功能层。Flutter 这里只负责权限、状态和开关控制；'
                '悬浮气泡、展开面板、调色画布、取色覆盖层、色板抽屉都在 Kotlin 原生服务里实现。',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton(
                        onPressed: _requestPermission,
                        child: const Text('前往授权'),
                      ),
                      OutlinedButton(
                        onPressed: _refreshStatus,
                        child: const Text('刷新状态'),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pigment 悬浮层',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _isActive
                            ? Icons.bubble_chart
                            : Icons.bubble_chart_outlined,
                        color: _isActive ? Colors.blue : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isActive ? '运行中' : '未启动',
                        style: TextStyle(
                          color: _isActive ? Colors.blue : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _hasPermission ? _start : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('启动 Pigment'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isActive ? _stop : null,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('停止悬浮层'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _InfoCard(
            title: '原生功能层',
            body:
                '1. 56dp 悬浮气泡，可拖拽与吸边\n'
                '2. 点击气泡展开玻璃面板\n'
                '3. 面板内原生画布支持绘制、撤销、重做、清空\n'
                '4. 面板可进入全屏取色层\n'
                '5. 取色完成后同步主色和色板抽屉',
          ),
          const SizedBox(height: 16),
          const _InfoCard(
            title: '说明',
            body:
                '这版遵循你的约束：功能层不在 Flutter 里复刻。后续如果继续补功能，应继续沿 Kotlin 服务、WindowManager overlay、MediaProjection 这条线扩展。',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(height: 1.5)),
          ],
        ),
      ),
    );
  }
}
