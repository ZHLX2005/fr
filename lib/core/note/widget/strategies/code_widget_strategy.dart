import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class CodeWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: CodeType(), icon: Icons.code, label: '<>', category: BlockTypeCategory.text),
  ];

  @override
  Widget buildEditor(BuildContext context, Block block, BlockCallbacks callbacks, {required Widget textField}) {
    final lang = (block.type as CodeType).language;
    final theme = Theme.of(context);
    return _CodeContainer(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          textField,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    final lang = (block.type as CodeType).language;
    final text = block.content.toPlainText();
    final theme = Theme.of(context);
    return _CodeContainer(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeContainer extends StatelessWidget {
  final ThemeData theme;
  final Widget child;

  const _CodeContainer({required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: theme.colorScheme.outlineVariant,
        radius: 8,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    const dash = 6.0;
    const gap = 4.0;
    var distance = 0.0;
    final dashedPath = Path();
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
        dashedPath.addPath(
          metric.extractPath(distance, end),
          Offset.zero,
        );
        distance += dash + gap;
      }
      distance = 0;
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
