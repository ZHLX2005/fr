// Demo 详情容器 — Lab 与游戏中心共用的「打开一个 DemoPage」外壳。
//
// 原为 lab_page.dart 的私有 _DemoDetailPage；游戏中心从 lab_page 的 part 解耦成
// 独立库后，这里提升为公共 widget，避免两处各写一份打开逻辑（行为漂移的源头）。
//
// 约定：demo.preferFullScreen == true 时不加 AppBar，由 demo 自管全屏布局与返回。

import 'package:flutter/material.dart';

import '../../../lab/lab_container.dart';

class DemoDetailPage extends StatelessWidget {
  const DemoDetailPage({super.key, required this.demo});

  final DemoPage demo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: demo.preferFullScreen
          ? null
          : AppBar(
              toolbarHeight: 48,
              titleTextStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              title: GestureDetector(
                onTap: () => _showDemoDesc(context),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  demo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
      body: demo.buildPage(context),
    );
  }

  void _showDemoDesc(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.widgets),
            const SizedBox(width: 8),
            Flexible(child: Text(demo.title)),
          ],
        ),
        content: Text(demo.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
