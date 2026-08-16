// 系统消息面板 —— 渲染 SystemEventsController 中的事件流。
//
// 通过 GetIt 拿 SystemEventsController，ListenableBuilder 监听变化。
// 空态显示占位提示，非空态按时间倒序展示。

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/factory/message_widget_factory.dart';
import 'system_events_controller.dart';

class SystemMessagesPanel extends StatelessWidget {
  const SystemMessagesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GetIt.instance<SystemEventsController>();
    final factory = GetIt.instance<MessageWidgetFactory>();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final events = controller.events;
        if (events.isEmpty) {
          return const _EmptyState();
        }
        // 倒序：最新事件在最上面
        final reversed = events.reversed.toList(growable: false);
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: reversed.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final ev = reversed[i];
            return factory.create(context, ev);
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              '暂无系统消息',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'APK 自动下载等后台事件触发后，会在此显示',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}