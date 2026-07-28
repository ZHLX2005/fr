import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock_record.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/clock_editor_sheet.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/zen_theme.dart';

/// Clocks tab — grid of clock cards + records list.
/// Preserves the core clock functionality (start/pause/reset, swipe-rename,
/// create-clock-from-record). The wave divider from the old design is gone;
/// the records list is shown below the grid.
class ClocksTab extends StatelessWidget {
  const ClocksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZenColors.bg,
      appBar: AppBar(
        backgroundColor: ZenColors.bg,
        elevation: 0,
        title: const Text('Clocks', style: ZenText.title),
      ),
      body: Consumer<LabClockProvider>(
        builder: (context, provider, _) {
          if (provider.clocks.isEmpty) {
            return _EmptyState(onAdd: () => _openEditor(context, provider));
          }
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ClockCard(clock: provider.clocks[i]),
                    childCount: provider.clocks.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text('Records', style: ZenText.label),
                ),
              ),
              if (provider.records.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text('No records yet.', style: ZenText.label),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _RecordTile(record: provider.records[i]),
                    childCount: provider.records.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<LabClockProvider>(
        builder: (context, provider, _) => FloatingActionButton(
          onPressed: () => _openEditor(context, provider),
          backgroundColor: ZenColors.sage,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, LabClockProvider provider,
      {LabClock? existing}) async {
    final result = await showClockEditor(context, existing: existing);
    if (result == null) return;
    if (existing == null) {
      await provider.createClock(
        title: result.title,
        description: result.description,
        durationSeconds: result.durationSeconds,
        color: result.color,
      );
      // setBeat is on the *newest* clock (inserted at index 0)
      final newest = provider.clocks.first;
      await provider.setBeat(
        newest.id,
        bpm: result.bpm,
        beatPattern: result.beatPattern,
      );
    } else {
      await provider.updateClock(
        id: existing.id,
        title: result.title,
        description: result.description,
        durationSeconds: result.durationSeconds,
        color: result.color,
      );
      await provider.setBeat(
        existing.id,
        bpm: result.bpm,
        beatPattern: result.beatPattern,
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 64, color: ZenColors.hair),
          const SizedBox(height: 16),
          const Text('No clocks yet', style: ZenText.label),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onAdd,
            style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
            child: const Text('Add clock'),
          ),
        ],
      ),
    );
  }
}

class _ClockCard extends StatelessWidget {
  final LabClock clock;
  const _ClockCard({required this.clock});

  @override
  Widget build(BuildContext context) {
    final p = context.read<LabClockProvider>();
    final baseColor = Color(int.parse(clock.color?.replaceFirst('#', '0xFF') ?? '0xFF2196F3'));
    final remaining = clock.remainingSeconds;
    final hasBeat = clock.bpm != null;
    final silenced = p.isClockSilenced(clock.id);
    final isActive = clock.isRunning && hasBeat && !silenced;

    return InkWell(
      onTap: () async {
        final result = await showClockEditor(context, existing: clock);
        if (result == null) return;
        await p.updateClock(
          id: clock.id,
          title: result.title,
          description: result.description,
          durationSeconds: result.durationSeconds,
          color: result.color,
        );
        await p.setBeat(clock.id, bpm: result.bpm, beatPattern: result.beatPattern);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: zenCard(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    clock.title,
                    style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _confirmDelete(context, p),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: ZenColors.secondary),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatTime(remaining),
                  style: ZenText.monoDigit.copyWith(
                    fontSize: 32,
                    color: remaining < 0 ? ZenColors.mutedRed : ZenColors.ink,
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (hasBeat)
              Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: isActive ? ZenColors.sage : Colors.transparent,
                      border: Border.all(color: isActive ? ZenColors.sage : ZenColors.secondary),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${clock.bpm}bpm ${clock.beatPattern ?? ""}'.trim(),
                      style: ZenText.monoDigitSmall),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlButton(
                  icon: clock.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: baseColor,
                  onTap: () => clock.isRunning
                      ? p.pauseCountdown(clock.id)
                      : p.startCountdown(clock.id),
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.refresh_rounded,
                  color: ZenColors.secondary,
                  onTap: () => p.resetCountdown(clock.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, LabClockProvider p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete clock'),
        content: Text('Delete "${clock.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { p.deleteClock(clock.id); Navigator.pop(ctx); },
            child: const Text('Delete', style: TextStyle(color: ZenColors.mutedRed)),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ControlButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44, height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final LabClockRecord record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final p = context.read<LabClockProvider>();
    final isCompleted = record.completed;
    final color = isCompleted ? ZenColors.sage : ZenColors.mutedRed;
    final dateStr = MaterialLocalizations.of(context).formatShortDate(record.startTime);

    return InkWell(
      onTap: () => _showActions(context, p),
      child: Container(
        decoration: zenCard(),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  Text(record.customTitle ?? record.clockTitle, style: ZenText.body),
                  Text(dateStr, style: ZenText.monoDigitSmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatDuration(p.getRecordLiveDuration(record)),
                style: ZenText.monoDigitSmall.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, LabClockProvider p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ZenColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(
              color: ZenColors.hair, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit, color: ZenColors.ink),
              title: const Text('Rename', style: ZenText.body),
              onTap: () { Navigator.pop(ctx); _rename(context, p); },
            ),
            ListTile(
              leading: const Icon(Icons.add, color: ZenColors.sage),
              title: const Text('Create clock from this', style: ZenText.body),
              onTap: () async {
                Navigator.pop(ctx);
                final dur = p.getRecordLiveDuration(record);
                if (dur > 0) {
                  await p.createClock(
                    title: record.customTitle ?? record.clockTitle,
                    durationSeconds: dur,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: ZenColors.mutedRed),
              title: const Text('Delete', style: TextStyle(color: ZenColors.mutedRed, fontSize: 16)),
              onTap: () { p.deleteRecord(record.id); Navigator.pop(ctx); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _rename(BuildContext context, LabClockProvider p) {
    final ctl = TextEditingController(text: record.customTitle ?? record.clockTitle);
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

String _formatTime(int seconds) {
  final isNegative = seconds < 0;
  final absSeconds = seconds.abs();
  final h = absSeconds ~/ 3600;
  final m = (absSeconds % 3600) ~/ 60;
  final s = absSeconds % 60;
  final sign = isNegative ? '-' : '';
  return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
