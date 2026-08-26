import 'package:flutter/material.dart';

import '../../data/lab_calendar_provider.dart';
import '../dsl/dsl_parser.dart';
import '../dsl/dsl_errors.dart';

/// 日历 DSL 导入对话框（v2）。
///
/// 用户粘贴 DSL 文本 → 解析 → 预览 → 应用到 LabCalendarProvider.applyDsl。
class CalendarImportDialog extends StatefulWidget {
  const CalendarImportDialog({super.key});

  @override
  State<CalendarImportDialog> createState() => _CalendarImportDialogState();
}

class _CalendarImportDialogState extends State<CalendarImportDialog> {
  final _controller = TextEditingController();
  ParseResult? _parsed;
  bool _applied = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _preview() {
    setState(() {
      _parsed = parseCalendarDsl(_controller.text);
    });
  }

  Future<void> _apply() async {
    final cal = LabCalendarProvider.current;
    if (cal == null) return;
    final report = await cal.applyDsl(_controller.text);
    if (!mounted) return;
    setState(() => _applied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已应用 ${report.added} 个事件，跳过 ${report.skipped}')),
    );
    Navigator.pop(context, report.added);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parsed;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      child: Container(
        width: 360,
        height: 480,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('日历 DSL 导入', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 8,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText:
                    'config { default-system=solar }\nevent "妈生日" { type=birthday period=yearly /month=04 /day=15 }',
                hintStyle: const TextStyle(fontSize: 11),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _preview,
                    child: const Text('预览'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: parsed == null || _applied ? null : _apply,
                    child: Text(_applied
                        ? '已应用'
                        : (parsed == null
                            ? '应用'
                            : '应用')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(theme, parsed)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ParseResult? parsed) {
    if (parsed == null) {
      return Center(
        child: Text(
          '粘贴 DSL 文本 → 点击预览',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (parsed.errors.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.error),
        ),
        child: ListView(
          children: parsed.errors
              .map((e) => Text(
                    e.toString(),
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 11,
                    ),
                  ))
              .toList(),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: ListView(
        children: [
          Text(
            '顶层语句 ${parsed.stmts.length} 条（无错误）',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final s in parsed.stmts.take(10))
            Text(
              '· ${s.runtimeType}',
              style: theme.textTheme.bodySmall,
            ),
          if (parsed.stmts.length > 10)
            Text(
              '… 还有 ${parsed.stmts.length - 10} 条',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

// Avoid unused import warning on DslError when file is short
typedef _Keep = DslError;