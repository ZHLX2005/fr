import 'package:flutter/material.dart';
import 'chat/agent_chat_page.dart';
import 'chat/format_compatibility_page.dart';

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

  const AssistantEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.builder,
  });
}

/// 功能列表单一数据源。加第三个功能 = 在此追加一项。
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
    subtitle: '格式兼容性测试',
    color: (context) => Theme.of(context).colorScheme.secondary,
    builder: (context) => const FormatCompatibilityPage(),
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
            const SizedBox(height: 32),
            Text(
              'AI 助手',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '选择功能',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
class _AssistantTile extends StatelessWidget {
  final AssistantEntry entry;

  const _AssistantTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.color(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(entry.icon, size: 28, color: color),
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
