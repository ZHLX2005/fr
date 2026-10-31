import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_gallery_log.dart';

/// 日志查看页 —— 设置页「日志模式」里进来，专门用来排查 AI 调用。
///
/// 只读 + 复制 + 清空；不做任何网络动作。列表按时间倒序（最新的在最上面，
/// 报错通常发生在最后一次尝试）。
class AiGalleryLogPage extends StatefulWidget {
  const AiGalleryLogPage({super.key});

  @override
  State<AiGalleryLogPage> createState() => _AiGalleryLogPageState();
}

class _AiGalleryLogPageState extends State<AiGalleryLogPage> {
  bool _onlyErrors = false;

  AiGalleryLog get _log => AiGalleryLog.instance;

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _log.exportText()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('只影响内存里的调试日志，不影响 AI 分析记录和图片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) _log.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _log,
        builder: (context, _) {
          final all = _log.entries.reversed.toList(growable: false);
          final list = _onlyErrors
              ? all
                    .where((e) => e.level == AiGalleryLogLevel.error)
                    .toList(growable: false)
              : all;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBar(
                enabled: _log.enabled,
                total: all.length,
                errors: _log.errorCount,
                maxEntries: _log.maxEntries,
                maxChars: _log.maxChars,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _FilterButton(
                      label: '全部 ${all.length}',
                      selected: !_onlyErrors,
                      onTap: () => setState(() => _onlyErrors = false),
                    ),
                    const SizedBox(width: 8),
                    _FilterButton(
                      label: '仅错误 ${_log.errorCount}',
                      selected: _onlyErrors,
                      onTap: () => setState(() => _onlyErrors = true),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _log.enabled
                                ? '还没有日志。扫描一次就会有了。'
                                : '日志模式未开启。\n回到上一页打开「日志模式」后再试。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                        itemBuilder: (context, i) => _LogTile(entry: list[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 顶部状态条：开关状态 + 容量配置 + 错误计数。
class _StatusBar extends StatelessWidget {
  final bool enabled;
  final int total;
  final int errors;
  final int maxEntries;
  final int maxChars;

  const _StatusBar({
    required this.enabled,
    required this.total,
    required this.errors,
    required this.maxEntries,
    required this.maxChars,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                enabled
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 14,
                color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                enabled ? '记录中' : '已停止记录',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (errors > 0)
                Text(
                  '$errors 条错误',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '共 $total 条 · 上限 $maxEntries 条 · 单条 ≤ $maxChars 字（超出截断）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 边框式筛选按钮（本页不额外增加实心色块）。
class _FilterButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条日志：点一下展开/收起，长按复制。
class _LogTile extends StatefulWidget {
  final AiGalleryLogEntry entry;

  const _LogTile({required this.entry});

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile> {
  bool _expanded = false;

  Color _levelColor(ColorScheme scheme) => switch (widget.entry.level) {
    AiGalleryLogLevel.error => scheme.error,
    AiGalleryLogLevel.warn => scheme.tertiary,
    AiGalleryLogLevel.info => scheme.primary,
    AiGalleryLogLevel.debug => scheme.onSurfaceVariant,
  };

  Future<void> _copy() async {
    final e = widget.entry;
    await Clipboard.setData(
      ClipboardData(
        text: '[${e.formattedTime}][${e.level.label}][${e.tag}] ${e.message}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('这一条已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = widget.entry;
    final color = _levelColor(scheme);
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      onLongPress: _copy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  e.formattedTime,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  e.level.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    e.tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              e.message,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (e.truncated && _expanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '（本条已按配置长度截断，完整内容请看原始请求/响应）',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
