// 系统消息面板 —— 渲染 SystemEventsController 中的事件流，
// 以 IM 聊天气泡方式呈现（最旧在上、最新在下，新事件自动滚到底部）。
//
// 通过 GetIt 拿 SystemEventsController，ListenableBuilder 监听变化。

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/factory/message_widget_factory.dart';
import 'system_events_controller.dart';

class SystemMessagesPanel extends StatefulWidget {
  const SystemMessagesPanel({super.key});

  @override
  State<SystemMessagesPanel> createState() => _SystemMessagesPanelState();
}

class _SystemMessagesPanelState extends State<SystemMessagesPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 新消息追加后滚到底部（IM 聊天惯例）。
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      _scrollController.jumpTo(pos.maxScrollExtent);
    });
  }

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
        // 首次构建后滚到底；后续 append 由 _scrollToBottom 触发
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: events.length,
          itemBuilder: (context, i) => factory.create(context, events[i]),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              size: 56,
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无系统消息',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '小助手会在后台事件触发后向你汇报',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}