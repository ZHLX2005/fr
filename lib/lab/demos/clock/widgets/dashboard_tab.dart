import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_track_provider.dart';
import 'package:xiaodouzi_fr/core/theme/component/zen/zen_theme.dart';

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
            padding: EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _StatTile(label: '今天', value: formatDuration(todaySeconds))),
                  SizedBox(width: 12),
                  Expanded(child: _StatTile(label: '完成时钟', value: '$clocksDone')),
                  SizedBox(width: 12),
                  Expanded(child: _StatTile(label: '完成编排', value: '$tracksDone')),
                ],
              ),
              SizedBox(height: 24),
              Text('最近', style: ZenText.label),
              SizedBox(height: 8),
              if (recent.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('暂无记录。', style: ZenText.label),
                )
              else
                ...recent.map((r) => Container(
                      margin: EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.all(12),
                      decoration: zenCardTheme(context),
                      child: Row(
                        children: [
                          Icon(
                            r.isClock ? Icons.access_time : Icons.queue_music,
                            color: context.colors.textMuted,
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.title, style: ZenText.body),
                                Text(
                                  '${formatRecordDate(r.startTime)} · 实际 ${formatDuration(r.durationSeconds)}',
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
