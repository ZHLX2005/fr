import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_track_provider.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

/// Dashboard tab content. Plain widgets — the shell owns the Scaffold/AppBar.
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<LabClockProvider, LabTrackProvider>(
        builder: (context, cp, tp, _) {
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          int todaySeconds = 0;
          for (final r in cp.records) {
            if (r.startTime.isAfter(todayStart)) {
              todaySeconds += cp.getRecordLiveDuration(r);
            }
          }
          for (final r in tp.records) {
            if (r.startTime.isAfter(todayStart)) {
              todaySeconds += tp.getRecordLiveDuration(r);
            }
          }
          final clocksDone = cp.records.where((r) => r.completed).length;
          final tracksDone = tp.records.where((r) => r.completed).length;

          // Merge and sort recent records
          final merged = <_RecentItem>[
            ...cp.records.map((r) => _RecentItem(
                  title: r.customTitle ?? r.clockTitle,
                  startTime: r.startTime,
                  durationSeconds: cp.getRecordLiveDuration(r),
                  isClock: true,
                )),
            ...tp.records.map((r) => _RecentItem(
                  title: r.customTitle ?? r.trackTitle,
                  startTime: r.startTime,
                  durationSeconds: tp.getRecordLiveDuration(r),
                  isClock: false,
                )),
          ]..sort((a, b) => b.startTime.compareTo(a.startTime));
          final recent = merged.take(5).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'Today', value: formatDuration(todaySeconds))),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: 'Clocks done', value: '$clocksDone')),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: 'Tracks done', value: '$tracksDone')),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Recent', style: ZenText.label),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No records yet.', style: ZenText.label),
                )
              else
                ...recent.map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: zenCard(),
                      child: Row(
                        children: [
                          Icon(
                            r.isClock ? Icons.access_time : Icons.queue_music,
                            color: ZenColors.secondary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.title, style: ZenText.body),
                                Text(
                                  '${MaterialLocalizations.of(context).formatShortDate(r.startTime)} · actual ${formatDuration(r.durationSeconds)}',
                                  style: ZenText.monoDigitSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
            ],
          );
        },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ZenSection(
      title: label,
      child: Text(value, style: ZenText.monoDigit.copyWith(fontSize: 24)),
    );
  }
}

class _RecentItem {
  final String title;
  final DateTime startTime;
  final int durationSeconds;
  final bool isClock;
  _RecentItem({
    required this.title,
    required this.startTime,
    required this.durationSeconds,
    required this.isClock,
  });
}
