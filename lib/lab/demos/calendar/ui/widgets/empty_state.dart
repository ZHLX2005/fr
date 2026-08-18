import 'package:flutter/material.dart';
import '../../../../../widgets/context_colors.dart';

import '../../../../../core/theme/typography.dart';

class EmptyState extends StatelessWidget {
  final String message;
  EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(message, style: AppText.body(color: context.colors.textMuted)),
      ),
    );
  }
}