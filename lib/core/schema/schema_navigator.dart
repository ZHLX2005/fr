// Schema 路由导航器
//
// 处理 schema:// 协议的路由分发

import 'package:flutter/material.dart';
import '../../lab/lab_container.dart';

/// Schema 导航服务（纯静态方法）
class SchemaNavigator {
  SchemaNavigator._();

  /// 全局导航 Key（需要外部设置）
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// 设置导航 Key
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 获取当前 NavigatorState
  static NavigatorState? get _navigatorState {
    return _navigatorKey?.currentState;
  }

  /// 获取当前上下文
  static BuildContext? get _context {
    return _navigatorKey?.currentContext;
  }

  /// 跳转到指定 schema
  static Future<void> navigateToSchema(String schema) async {
    final context = _context;
    if (context == null) {
      debugPrint('SchemaNavigator: 无法获取导航上下文');
      return;
    }

    if (!schema.startsWith('fr://')) {
      debugPrint('SchemaNavigator: 无效的 schema: $schema');
      return;
    }

    final path = schema.substring('fr://'.length);

    if (path.startsWith('lab/demo/')) {
      // 跳转到 Demo 页面
      final demoKey = path.substring('lab/demo/'.length);
      await navigateToDemo(demoKey, context);
    } else if (path == 'lab' || path == 'lab/') {
      // 跳转到 Lab 页面
      await navigateToLab(context);
    } else {
      debugPrint('SchemaNavigator: 未知的路径: $path');
    }
  }

  /// 跳转到 Demo 页面
  static Future<void> navigateToDemo(String demoKey, BuildContext context) async {
    final demo = demoRegistry.get(demoKey);

    if (demo == null) {
      // 尝试模糊匹配
      final allDemos = demoRegistry.getAll();
      final matched = allDemos.where(
        (e) => e.key.contains(demoKey) || e.value.title.contains(demoKey),
      ).toList();

      if (matched.length == 1) {
        await _openDemoDetail(matched.first.key, context);
      } else if (matched.isEmpty) {
        _showError(context, '未找到 Demo: $demoKey');
      } else {
        // 多个匹配，显示选择器
        await _showDemoSelector(context, matched);
      }
      return;
    }

    await _openDemoDetail(demoKey, context);
  }

  /// 跳转到 Lab 页面
  static Future<void> navigateToLab(BuildContext context) async {
    _navigatorState?.push(
      MaterialPageRoute(
        builder: (_) => const _LabPageContent(),
        settings: const RouteSettings(name: '/lab'),
      ),
    );
  }

  /// 打开 Demo 详情页
  static Future<void> _openDemoDetail(String demoKey, BuildContext context) async {
    final demo = demoRegistry.get(demoKey);
    if (demo == null) return;

    // 先返回到 Lab 页面
    _navigatorState?.popUntil((route) => route.settings.name == '/lab' || route.isFirst);

    // 延迟打开详情页，等待导航完成
    await Future.delayed(const Duration(milliseconds: 100));

    if (!context.mounted) return;

    _navigatorState?.push(
      MaterialPageRoute(
        builder: (_) => _DemoDetailPage(demo: demo),
        settings: RouteSettings(name: '/lab/demo', arguments: demoKey),
      ),
    );
  }

  /// 显示 Demo 选择器
  static Future<void> _showDemoSelector(
    BuildContext context,
    List<MapEntry<String, DemoPage>> demos,
  ) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        itemCount: demos.length,
        itemBuilder: (_, i) {
          final entry = demos[i];
          final demo = entry.value;
          return ListTile(
            title: Text(demo.title),
            subtitle: Text(demo.description),
            onTap: () {
              Navigator.pop(ctx);
              _openDemoDetail(entry.key, context);
            },
          );
        },
      ),
    );
  }

  /// 显示错误提示
  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// Lab 页面内容（简化版）
class _LabPageContent extends StatelessWidget {
  const _LabPageContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lab'),
      ),
      body: const Center(
        child: Text('请从首页进入 Lab'),
      ),
    );
  }
}

/// Demo 详情页
class _DemoDetailPage extends StatelessWidget {
  final DemoPage demo;

  const _DemoDetailPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return demo.buildPage(context);
  }
}
