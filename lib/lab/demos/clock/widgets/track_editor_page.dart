import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

Future<LabTrack?> showTrackEditor(BuildContext context, {LabTrack? existing}) {
  return Navigator.push<LabTrack>(
    context,
    MaterialPageRoute(
      builder: (_) => TrackEditorPage(existing: existing),
      fullscreenDialog: true,
    ),
  );
}

class TrackEditorPage extends StatefulWidget {
  final LabTrack? existing;
  const TrackEditorPage({super.key, this.existing});

  @override
  State<TrackEditorPage> createState() => _TrackEditorPageState();
}

class _TrackEditorPageState extends State<TrackEditorPage> {
  late TextEditingController _titleCtl;
  late TextEditingController _descCtl;
  late List<LabTrackSegment> _segments;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.existing?.title ?? '');
    _descCtl = TextEditingController(text: widget.existing?.description ?? '');
    _segments = List<LabTrackSegment>.from(widget.existing?.segments ?? const []);
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  int get _totalSeconds =>
      _segments.fold(0, (s, seg) => s + seg.snapshotDurationSeconds);

  void _appendClock(LabClock clock) {
    setState(() {
      _segments.add(LabTrackSegment(
        clockId: clock.id,
        snapshotTitle: clock.title,
        snapshotColor: clock.color,
        snapshotDurationSeconds: clock.durationSeconds ?? 60,
        snapshotBpm: clock.bpm,
        snapshotBeatPattern: clock.beatPattern,
      ));
    });
  }

  void _removeSegment(int i) {
    setState(() => _segments.removeAt(i));
  }

  void _moveUp(int i) {
    if (i == 0) return;
    setState(() {
      final s = _segments.removeAt(i);
      _segments.insert(i - 1, s);
    });
  }

  void _moveDown(int i) {
    if (i == _segments.length - 1) return;
    setState(() {
      final s = _segments.removeAt(i);
      _segments.insert(i + 1, s);
    });
  }

  void _save() {
    if (_titleCtl.text.trim().isEmpty || _segments.isEmpty) return;
    final id = widget.existing?.id ?? const Uuid().v4();
    final created = widget.existing?.createdAt ?? DateTime.now();
    Navigator.pop(
      context,
      LabTrack(
        id: id,
        title: _titleCtl.text.trim(),
        description: _descCtl.text,
        createdAt: created,
        segments: _segments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZenColors.bg,
      appBar: AppBar(
        backgroundColor: ZenColors.bg,
        elevation: 0,
        title: Text(widget.existing == null ? 'New track' : 'Edit track', style: ZenText.title),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: OutlinedButton(
              onPressed: _segments.isEmpty ? null : _save,
              style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtl,
            style: ZenText.body,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtl,
            style: ZenText.body,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Source', style: ZenText.label),
          const SizedBox(height: 8),
          Consumer<LabClockProvider>(
            builder: (context, provider, _) {
              if (provider.clocks.isEmpty) {
                return const Text('No clocks — add some first.', style: ZenText.label);
              }
              return SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: provider.clocks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = provider.clocks[i];
                    final color = Color(int.parse(c.color?.replaceFirst('#', '0xFF') ?? '0xFF2196F3'));
                    return InkWell(
                      onTap: () => _appendClock(c),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 120,
                        padding: const EdgeInsets.all(8),
                        decoration: zenCard(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(c.title, style: ZenText.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                            const Spacer(),
                            Text(_formatDuration(c.durationSeconds ?? 0), style: ZenText.monoDigitSmall),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('Sequence', style: ZenText.label),
          const SizedBox(height: 8),
          if (_segments.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: zenDottedZone(),
              child: const Center(
                child: Text('Tap a clock above to add to the track', style: ZenText.label),
              ),
            )
          else
            ...List.generate(_segments.length, (i) {
              final seg = _segments[i];
              final color = seg.snapshotColor != null
                  ? Color(int.parse(seg.snapshotColor!.replaceFirst('#', '0xFF')))
                  : ZenColors.ink;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: zenCard(),
                child: Row(
                  children: [
                    Text('${i + 1}', style: ZenText.monoDigitSmall),
                    const SizedBox(width: 12),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(seg.snapshotTitle, style: ZenText.body),
                          if (seg.snapshotBpm != null)
                            Text('${seg.snapshotBpm}bpm ${seg.snapshotBeatPattern ?? ""}', style: ZenText.monoDigitSmall),
                        ],
                      ),
                    ),
                    Text(_formatDuration(seg.snapshotDurationSeconds), style: ZenText.monoDigitSmall),
                    IconButton(
                      onPressed: i == 0 ? null : () => _moveUp(i),
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      tooltip: 'Move up',
                    ),
                    IconButton(
                      onPressed: i == _segments.length - 1 ? null : () => _moveDown(i),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      tooltip: 'Move down',
                    ),
                    IconButton(
                      onPressed: () => _removeSegment(i),
                      icon: const Icon(Icons.close, size: 20, color: ZenColors.mutedRed),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: zenCard(color: ZenColors.surface),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: ZenText.label),
                Text(_formatDuration(_totalSeconds), style: ZenText.monoDigit.copyWith(fontSize: 20)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}
