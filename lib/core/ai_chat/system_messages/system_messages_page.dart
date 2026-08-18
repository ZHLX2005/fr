// 系统消息独立页 —— 提供 fr:// 路由直达入口。
// 主要挂在 AI 助手页的第 4 项"小助手"；保留独立页便于从其它路径
// （桌面 widget / 通知中心）直接跳进来。
//
// 进入页面后调用 markAllRead() 清零未读徽章，让 HomePage 上的红点消失。

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'system_messages_panel.dart';
import 'system_events_controller.dart';

class SystemMessagesPage extends StatefulWidget {
  const SystemMessagesPage({super.key});

  @override
  State<SystemMessagesPage> createState() => _SystemMessagesPageState();
}

class _SystemMessagesPageState extends State<SystemMessagesPage> {
  @override
  void initState() {
    super.initState();
    // 进入即视为"已读"，清零 HomePage 红点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GetIt.instance<SystemEventsController>().markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = GetIt.instance<SystemEventsController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('小助手 · 系统消息'),
        centerTitle: true,
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (controller.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '清空全部',
                onPressed: () => _confirmClear(context, controller),
              );
            },
          ),
        ],
      ),
      body: const SystemMessagesPanel(),
    );
  }

  Future<void> _confirmClear(
      BuildContext context, SystemEventsController controller) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空系统消息'),
        content: const Text('确定要清空全部系统消息吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) controller.clear();
  }
}