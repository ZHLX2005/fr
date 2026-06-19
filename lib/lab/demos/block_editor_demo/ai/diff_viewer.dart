import 'package:flutter/material.dart';

/// 方案 A diff 展示：按行渲染，`+` 绿、`-` 红、`@@` 灰、其余默认。monospace。
class DiffViewer extends StatelessWidget {
  final String diff;
  final int maxLines;

  const DiffViewer({super.key, required this.diff, this.maxLines = 12});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = diff.isEmpty ? <String>[] : diff.split('\n');

    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: BoxConstraints(maxHeight: 28.0 * maxLines),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          return Text(
            line.isEmpty ? ' ' : line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
              color: _colorFor(line, theme),
            ),
          );
        },
      ),
    );
  }

  Color _colorFor(String line, ThemeData theme) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      return theme.colorScheme.onSurfaceVariant;
    }
    if (line.startsWith('+')) {
      return Colors.green.shade700;
    }
    if (line.startsWith('-')) {
      return Colors.red.shade700;
    }
    if (line.startsWith('@@')) {
      return theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    }
    return theme.colorScheme.onSurface;
  }
}
