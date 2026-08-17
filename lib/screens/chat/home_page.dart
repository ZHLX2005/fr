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
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题区：紧凑
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'AI 助手',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            // 列表：无边框设计，仅靠细分隔线隐式划界
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _entries.length,
                // 分隔线：从图标右侧开始（22 icon + 14 gap + 16 padding = 52），
                // 细淡色，高度极小，视觉上只是一道隐约的线
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 52,
                  endIndent: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
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

/// IM 风格功能条目：紧凑无边框，图标 + 标题/副标题 + 箭头，靠左侧对齐。
/// 高度 ~52px（原来的 60%），4 条 items 在同屏内不溢出。
class _AssistantTile extends StatelessWidget {
  final AssistantEntry entry;

  const _AssistantTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.color(context);
    final badge = entry.badgeBuilder?.call(context);
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: entry.builder),
          );
        },
        // 左对齐：去掉 ListTile 默认的大水平 padding
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // 左侧图标：无圆形容器，纯色图标 + badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(entry.icon, size: 22, color: color),
                  if (badge != null)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: badge,
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // 中间：标题 + 副标题（垂直对齐，标题加粗，副标题浅色小字）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              // 右侧箭头：弱化，用 opacity 控制
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
