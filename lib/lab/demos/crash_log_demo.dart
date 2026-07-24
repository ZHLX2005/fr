import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';

class CrashLogDemo extends DemoPage {
  @override
  String get title => 'Crash日志';

  @override
  String get slug => 'crash-log';

  @override
  String get description => '查看App崩溃日志';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const CrashLogDemoPage();
}

class CrashLogDemoPage extends StatefulWidget {
  const CrashLogDemoPage({super.key});

  @override
  State<CrashLogDemoPage> createState() => _CrashLogDemoPageState();
}

class _CrashLogDemoPageState extends State<CrashLogDemoPage> {
  static final _channel = MethodChannel('io.github.xiaodouzi.fr/crash');
  List<Map<String, String>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final logs = await _channel.invokeMethod<List>('getCrashLogs');
      _logs = logs
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          [];
    } catch (e) {
      _logs = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _clearLogs() async {
    await _channel.invokeMethod('clearCrashLogs');
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash日志'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清除日志'),
                    content: const Text('确定清除所有Crash日志？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _clearLogs();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                        ),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.shade300,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无Crash日志',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'App运行良好，继续保持',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final time = log['time'] ?? '';
                    final content = log['content'] ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: const Icon(Icons.error_outline, color: Colors.red),
                        title: Text(
                          time.replaceAll('_', ' ').replaceAll('-', '/'),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              content,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

void registerCrashLogDemo() {
  demoRegistry.register(CrashLogDemo());
}
