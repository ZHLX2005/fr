import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_track_provider.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

class TrackRunnerPage extends StatefulWidget {
  final String trackId;
  const TrackRunnerPage({super.key, required this.trackId});

  @override
  State<TrackRunnerPage> createState() => _TrackRunnerPageState();
}

class _TrackRunnerPageState extends State<TrackRunnerPage> {
  Timer? _ticker;
  bool _autoPopped = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final p = context.read<LabTrackProvider>();
      if (p.activeTrackId == null && !_autoPopped) {
        _autoPopped = true;
        _ticker?.cancel();
        Future.microtask(() {
          if (mounted) Navigator.of(context).pop();
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LabTrackProvider>(
      builder: (context, p, _) {
        final track = p.tracks.firstWhere(
          (t) => t.id == widget.trackId,
          orElse: () => LabTrack(
            id: widget.trackId,
            title: 'Track',
            createdAt: DateTime.now(),
            segments: const [],
          ),
        );
        if (track.segments.isEmpty) {
          return Scaffold(
            backgroundColor: ZenColors.bg,
            appBar: AppBar(backgroundColor: ZenColors.bg, elevation: 0),
            body: const Center(child: Text('Empty track', style: ZenText.body)),
          );
        }
        final idx = p.currentSegmentIndex.clamp(0, track.segments.length - 1);
        final seg = track.segments[idx];
        final segRem = p.currentSegmentRemaining;
        final totalRem = p.totalRemaining;
        final segDur = seg.snapshotDurationSeconds;
        final segProgress = segDur > 0 ? (segDur - segRem) / segDur : 0.0;
        final totalDur = track.segments.fold<int>(0, (s, e) => s + e.snapshotDurationSeconds);
        final totalProgress = totalDur > 0 ? 1 - totalRem / totalDur : 0.0;
        final isPaused = p.activeTrackId == null;
        final hasBeat = seg.snapshotBpm != null;

        return Scaffold(
          backgroundColor: ZenColors.bg,
          appBar: AppBar(
            backgroundColor: ZenColors.bg,
            elevation: 0,
            title: Text(track.title, style: ZenText.title),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Segment ${idx + 1} of ${track.segments.length}', style: ZenText.label),
                const SizedBox(height: 16),
                Text(seg.snapshotTitle, style: ZenText.title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    formatTime(segRem),
                    style: ZenText.monoDigitLarge.copyWith(
                      color: segRem < 0 ? ZenColors.mutedRed : ZenColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _ProgressBar(progress: segProgress.clamp(0.0, 1.0), label: 'Segment'),
                const SizedBox(height: 8),
                _ProgressBar(progress: totalProgress.clamp(0.0, 1.0), label: 'Track'),
                const SizedBox(height: 24),
                if (hasBeat) _BeatDotRow(active: !isPaused, count: 4),
                const Spacer(),
                Text('Total remaining: ${formatTime(totalRem)}', style: ZenText.monoDigitSmall, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RunnerButton(
                      icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      label: isPaused ? 'Resume' : 'Pause',
                      onTap: () => isPaused
                          ? p.startTrack(widget.trackId)
                          : p.pauseTrack(),
                    ),
                    _RunnerButton(
                      icon: Icons.skip_next_rounded,
                      label: 'Skip',
                      onTap: () => p.skipSegment(),
                    ),
                    _RunnerButton(
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      onTap: () async {
                        // 熄灭 ticker 的自动 pop，避免 300ms 退出动画期间二次 pop
                        // → 内层 Navigator 被弹空 → 白屏整页退出
                        _ticker?.cancel();
                        _autoPopped = true;
                        final nav = Navigator.of(context);
                        await p.stopTrack();
                        if (mounted) nav.pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final String label;
  const _ProgressBar({required this.progress, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ZenText.label),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: ZenColors.hair,
            valueColor: const AlwaysStoppedAnimation(ZenColors.sage),
          ),
        ),
      ],
    );
  }
}

class _BeatDotRow extends StatelessWidget {
  final bool active;
  final int count;
  const _BeatDotRow({required this.active, required this.count});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ZenDot(active: active),
      )),
    );
  }
}

class _RunnerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RunnerButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZenIconButton(icon: icon, onTap: onTap),
        const SizedBox(height: 4),
        Text(label, style: ZenText.label),
      ],
    );
  }
}
