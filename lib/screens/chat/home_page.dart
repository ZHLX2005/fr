import 'package:flutter/material.dart';
import '../../core/ai_chat/ai_chat_format/format_compatibility_page.dart';
import '../../core/ai_chat/ai_chat_sports/agent_chat_page.dart';
import '../../core/ai_chat/receipt_ocr/receipt_ocr_page.dart';
import '../../core/ai_chat/system_messages/system_events_controller.dart';
import '../../core/ai_chat/system_messages/system_messages_page.dart';

/// AI 助手功能入口条目配置。
///
/// 一个条目 = 一份配置：纯数据 + 目标页面构造闭包，
/// 将「有哪些功能」与「怎么渲染」解耦。新增功能只需往
/// [_entries] 追加一项。
class AssistantEntry {
  final IconData icon;
  final String title; // 主题
  final String subtitle; // 简介
  final Color Function(BuildContext) color; // 主题色（依赖 Theme）
  final Widget Function(BuildContext) builder; // 目标页面

  /// 可选徽章（如"未读消息数"小红点）。传 null 则不显示。
  /// 用 builder 是因为未读数通常是响应式数据（需要 ListenableBuilder）。
  final Widget Function(BuildContext)? badgeBuilder;

  const AssistantEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.builder,
    this.badgeBuilder,
  });
}

/// 功能列表单一数据源。加第 N 个功能 = 在此追加一项。
final List<AssistantEntry> _entries = [
  AssistantEntry(
    icon: Icons.assistant,
    title: 'Agent',
    subtitle: '事件记录与分析',
    color: (context) => Theme.of(context).colorScheme.primary,
    builder: (context) => const AgentChatPage(title: 'Agent'),
  ),
  AssistantEntry(
    icon: Icons.format_align_left,
    title: 'Format',
    subtitle: '消息策略聚合（含登录/注册）',
    color: (context) => Theme.of(context).colorScheme.secondary,
    builder: (context) => const FormatCompatibilityPage(),
  ),
  AssistantEntry(
    icon: Icons.receipt_long,
    title: '小票',
    subtitle: 'OCR 识别 → 快速比价',
    color: (context) => Theme.of(context).colorScheme.tertiary,
    builder: (context) => const ReceiptOcrPage(),
  ),
  AssistantEntry(
    icon: Icons.smart_toy,
    title: '小助手',
    subtitle: '后台事件汇报（APK 下载 / 崩溃日志）',
    color: (context) => Colors.teal,
    builder: (context) => const SystemMessagesPage(),
    // 未读系统消息数（响应式：监听 SystemEventsController）
    badgeBuilder: (context) => ListenableBuilder(
      listenable: SystemEventsController(),
      builder: (context, _) {
        final n = SystemEventsController().unreadCount;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            n > 99 ? '99+' : '$n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    ),
  ),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'AI 助手',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _entries.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  indent: 84,
                  endIndent: 16,
                ),
                itemBuilder: (context, index) =>
                    _AssistantTile(entry: _entries[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// IM 风格功能条目：最左圆形头像图标、中间主题+简介、最右进入箭头。
/// 可选徽章（如未读数）显示在头像右上角。
class _AssistantTile extends StatelessWidget {
  final AssistantEntry entry;

  const _AssistantTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.color(context);
    final badge = entry.badgeBuilder?.call(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(entry.icon, size: 28, color: color),
          ),
          if (badge != null)
            Positioned(
              right: -4,
              top: -4,
              child: badge,
            ),
        ],
      ),
      title: Text(
        entry.title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        entry.subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: entry.builder),
        );
      },
    );
  }
}
