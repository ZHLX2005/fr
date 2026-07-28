import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/zen_theme.dart';

/// Placeholder for Task 14 (TrackRecordsPage).
/// Replaced with full implementation in Task 14.
class TrackRecordsPage extends StatelessWidget {
  const TrackRecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZenColors.bg,
      appBar: AppBar(
        backgroundColor: ZenColors.bg,
        elevation: 0,
        title: const Text('Track records', style: ZenText.title),
      ),
      body: const Center(child: Text('Coming soon', style: ZenText.label)),
    );
  }
}
