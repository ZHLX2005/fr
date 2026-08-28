import 'package:flutter/material.dart';

import '../../../../../core/theme/component/calendar/paper_palette.dart';
import '../../../../../core/theme/typography.dart';

class EmptyState extends StatelessWidget {
  final String message;
  const EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: AppText.body(color: pp.inkMuted)),
      ),
    );
  }
}