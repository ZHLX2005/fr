import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_track_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/track_editor_page.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/track_runner_page.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

/// Tracks tab content. Plain widgets — the shell owns the Scaffold/FAB.
class TracksTab extends StatefulWidget {
  /// Optional callback invoked when the State mounts so the parent shell can
  /// call our [openEditor] from its FAB.
  final void Function(Future<void> Function(BuildContext) openEditor)? onReady;
  const TracksTab({super.key, this.onReady});

  @override
  State<TracksTab> createState() => _TracksTabState();
}

class _TracksTabState extends State<TracksTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady?.call(_openEditor);
    });
  }

  /// Called by the shell's FAB when the user is on the Tracks tab.
  Future<void> _openEditor(BuildContext context) async {
    final tp = context.read<LabTrackProvider>();
    final result = await showTrackEditor(context);
    if (result == null) return;
    await tp.createTrack(result);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LabTrackProvider, LabClockProvider>(
      builder: (context, tp, cp, _) {
        if (tp.tracks.isEmpty) {
          return const ZenEmptyState(
            icon: Icons.queue_music_outlined,
            message: '暂无编排',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: tp.tracks.length,
          itemBuilder: (_, i) => _TrackCard(
            track: tp.tracks[i],
            beatLocked: cp.activeBeatClockId != null,
            otherTrackRunning: tp.activeTrackId != null,
          ),
        );
      },
    );
  }
}

class _TrackCard extends StatelessWidget {
  final LabTrack track;
  final bool beatLocked;
  final bool otherTrackRunning;

  const _TrackCard({
    required this.track,
    required this.beatLocked,
    required this.otherTrackRunning,
  });

  @override
  Widget build(BuildContext context) {
    final tp = context.read<LabTrackProvider>();
    final totalSeconds = track.segments.fold(0, (s, seg) => s + seg.snapshotDurationSeconds);
    final canRun = track.segments.isNotEmpty && !beatLocked && !otherTrackRunning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: zenCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(track.title, style: ZenText.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${track.segments.length} 段 · ${formatDuration(totalSeconds)}',
              style: ZenText.monoDigitSmall),
          if (track.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(track.description, style: ZenText.label),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canRun
                      ? () async {
                          await tp.startTrack(track.id);
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => TrackRunnerPage(trackId: track.id)),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始'),
                  style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final result = await showTrackEditor(context, existing: track);
                  if (result == null) return;
                  await tp.updateTrack(result);
                },
                style: zenButton(),
                child: const Text('编辑'),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _confirmDelete(context, tp),
                icon: const Icon(Icons.delete_outline, color: ZenColors.mutedRed),
                tooltip: '删除',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, LabTrackProvider tp) {
    ZenConfirmDialog.show(
      context: context,
      title: '删除编排',
      message: '删除"${track.title}"？',
      onConfirm: () => tp.deleteTrack(track.id),
    );
  }
}
