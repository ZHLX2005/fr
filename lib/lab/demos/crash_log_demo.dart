import 'package:flutter/material.dart';
import '../../widgets/context_colors.dart';
import 'package:flutter/services.dart';
import '../../core/design/emphasis_button.dart';
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
        title: Text('Crash日志'),
        backgroundColor: context.colors.scheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
          if (_logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline),
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
                        style: EmphasisButton.dangerEmphasis(context),
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
          ? Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(height: 16),
                      const Text(
                        '暂无Crash日志',
                        style: TextStyle(fontSize: 18),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'App运行良好，继续保持',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final time = log['time'] ?? '';
                    final content = log['content'] ?? '';
                    return Card(
                      margin: EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                        title: Text(
                          time.replaceAll('_', ' ').replaceAll('-', '/'),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        childrenPadding: EdgeInsets.all(12),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              content,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
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
