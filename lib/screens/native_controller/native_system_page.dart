import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 原生系统功能测试页面
/// 用于测试应用使用时长查询、震动等系统级功能
class NativeSystemPage extends StatefulWidget {
  const NativeSystemPage({super.key});

  @override
  State<NativeSystemPage> createState() => _NativeSystemPageState();
}

class _NativeSystemPageState extends State<NativeSystemPage> {
  static const _systemChannel = MethodChannel('com.example.flutter_application_1/system');
  static const _clockChannel = MethodChannel('com.example.flutter_application_1/clock');

  bool _isLoading = false;
  bool _hasUsagePermission = false;
  List<AppUsageInfo> _appUsageList = [];
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _checkUsagePermission();
  }

  /// 检查使用统计权限
  Future<void> _checkUsagePermission() async {
    if (!Platform.isAndroid) {
      setState(() {
        _hasUsagePermission = false;
        _testResult = '应用使用时长查询仅支持 Android 平台';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final hasPermission = await _systemChannel.invokeMethod<bool>('checkUsagePermission');
      setState(() {
        _hasUsagePermission = hasPermission ?? false;
        _isLoading = false;
        _testResult = hasPermission == true
            ? '已授予使用统计权限'
            : '未授予使用统计权限，请先授权';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _testResult = '检查权限失败: $e';
      });
    }
  }

  /// 打开使用统计设置页面
  Future<void> _openUsageSettings() async {
    try {
      await _systemChannel.invokeMethod('openUsageSettings');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请在设置中授予"使用情况访问权限"'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开设置失败: $e')),
        );
      }
    }
  }

  /// 查询应用使用时长
  Future<void> _queryAppUsage() async {
    if (!Platform.isAndroid) {
      setState(() {
        _testResult = '应用使用时长查询仅支持 Android 平台';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _testResult = '正在查询应用使用时长...';
      _appUsageList = [];
    });

    try {
      final result = await _systemChannel.invokeMethod('queryAppUsage');
      if (result is List) {
        final list = result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((e) => AppUsageInfo(
                  packageName: e['packageName'] as String? ?? '',
                  appName: e['appName'] as String? ?? e['packageName'] ?? '',
                  totalTimeInForeground: e['totalTimeInForeground'] as int? ?? 0,
                  lastTimeUsed: e['lastTimeUsed'] as int? ?? 0,
                ))
            .toList()
          ..sort((a, b) => b.totalTimeInForeground.compareTo(a.totalTimeInForeground));

        setState(() {
          _appUsageList = list.take(20).toList(); // 只显示前20个
          _isLoading = false;
          _testResult = '查询成功，共找到 ${list.length} 个应用';
        });
      } else {
        setState(() {
          _isLoading = false;
          _testResult = '查询失败：返回数据格式错误';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _testResult = '查询失败: $e';
      });
    }
  }

  /// 震动测试
  Future<void> _vibrate({int duration = 300}) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(() {
        _testResult = '震动功能仅支持移动端';
      });
      return;
    }

    try {
      await _clockChannel.invokeMethod('vibrate', {'duration': duration});
      setState(() {
        _testResult = '震动 ${duration}ms';
      });
    } catch (e) {
      setState(() {
        _testResult = '震动失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统功能测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkUsagePermission,
            tooltip: '重新检查权限',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 权限状态卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _hasUsagePermission ? Icons.check_circle : Icons.error_outline,
                          color: _hasUsagePermission ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '使用统计权限',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _hasUsagePermission
                          ? '已授予使用情况访问权限，可以查询应用使用时长'
                          : '需要授予使用情况访问权限才能查询应用使用时长',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _hasUsagePermission
                            ? Colors.green
                            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (!_hasUsagePermission) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _openUsageSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('打开设置'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 震动测试卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.vibration, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '震动测试',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () => _vibrate(duration: 100),
                          child: const Text('轻震 (100ms)'),
                        ),
                        ElevatedButton(
                          onPressed: () => _vibrate(duration: 300),
                          child: const Text('中震 (300ms)'),
                        ),
                        ElevatedButton(
                          onPressed: () => _vibrate(duration: 500),
                          child: const Text('强震 (500ms)'),
                        ),
                        ElevatedButton(
                          onPressed: () => _vibrate(duration: 1000),
                          child: const Text('长震 (1000ms)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 查询按钮
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '应用使用时长查询',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '查询今日各应用的使用时长，按使用时间排序',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _hasUsagePermission && !_isLoading
                          ? _queryAppUsage
                          : null,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.query_stats),
                      label: Text(_isLoading ? '查询中...' : '查询今日应用使用时长'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 测试结果
            if (_testResult.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '操作结果',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(_testResult),
                    ],
                  ),
                ),
              ),

            // 应用使用时长列表
            if (_appUsageList.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日应用使用时长 (前${_appUsageList.length}名)',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _appUsageList.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final app = _appUsageList[index];
                          return _buildAppUsageItem(app, theme);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // 说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '注意事项',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 应用使用时长查询仅支持 Android 5.0+\n'
                    '• 需要用户手动授予"使用情况访问权限"\n'
                    '• 查询结果为今日（00:00 至今）的数据\n'
                    '• 震动功能仅支持移动端',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppUsageItem(AppUsageInfo app, ThemeData theme) {
    final hours = app.totalTimeInForeground ~/ 3600000;
    final minutes = (app.totalTimeInForeground % 3600000) ~/ 60000;
    final seconds = (app.totalTimeInForeground % 60000) ~/ 1000;

    String durationStr;
    if (hours > 0) {
      durationStr = '$hours小时 $minutes分钟';
    } else if (minutes > 0) {
      durationStr = '$minutes分钟 $seconds秒';
    } else {
      durationStr = '$seconds秒';
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        app.appName.isNotEmpty ? app.appName : app.packageName,
        style: theme.textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        app.packageName,
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        durationStr,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class AppUsageInfo {
  final String packageName;
  final String appName;
  final int totalTimeInForeground; // 毫秒
  final int lastTimeUsed; // 时间戳

  AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.totalTimeInForeground,
    required this.lastTimeUsed,
  });
}
