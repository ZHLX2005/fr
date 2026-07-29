import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track_record.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_track_provider.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

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
        actions: [
          Consumer<LabTrackProvider>(
            builder: (context, p, _) => p.records.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () => _confirmClear(context, p),
                    child: const Text('Clear', style: TextStyle(color: ZenColors.mutedRed)),
                  ),
          ),
        ],
      ),
      body: Consumer<LabTrackProvider>(
        builder: (context, p, _) {
          if (p.records.isEmpty) {
            return const Center(child: Text('No track records yet', style: ZenText.label));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: p.records.length,
            itemBuilder: (_, i) => _TrackRecordTile(record: p.records[i]),
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context, LabTrackProvider p) {
    ZenConfirmDialog.show(
      context: context,
      title: 'Clear track records',
      message: 'Clear all track records? This cannot be undone.',
      onConfirm: p.clearRecords,
      confirmLabel: 'Clear',
    );
  }
}

class _TrackRecordTile extends StatelessWidget {
  final LabTrackRecord record;
  const _TrackRecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final p = context.read<LabTrackProvider>();
    final isCompleted = record.completed;
    final color = isCompleted ? ZenColors.sage : ZenColors.mutedRed;
    final dateStr = MaterialLocalizations.of(context).formatShortDate(record.startTime);

    return InkWell(
      onLongPress: () => _rename(context, p),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: zenCard(),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCompleted ? Icons.check_rounded : Icons.schedule_rounded,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.customTitle ?? record.trackTitle, style: ZenText.body),
                  Text('$dateStr · planned ${formatDuration(record.totalDurationSeconds)} · actual ${formatDuration(p.getRecordLiveDuration(record))}',
                      style: ZenText.monoDigitSmall),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: ZenColors.mutedRed),
              onPressed: () => p.deleteRecord(record.id),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  void _rename(BuildContext context, LabTrackProvider p) {
    final ctl = TextEditingController(text: record.customTitle ?? record.trackTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename record'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = ctl.text.trim();
              if (v.isNotEmpty) p.updateRecordTitle(record.id, v);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
