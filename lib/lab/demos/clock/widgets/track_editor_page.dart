import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/core/theme/component/zen/zen_theme.dart';

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
    _segments = List<LabTrackSegment>.from(
      widget.existing?.segments ?? const [],
    );
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
      _segments.add(
        LabTrackSegment(
          clockId: clock.id,
          snapshotTitle: clock.title,
          snapshotColor: clock.color,
          snapshotDurationSeconds: clock.durationSeconds ?? 60,
          snapshotBpm: clock.bpm,
          snapshotBeatPattern: clock.beatPattern,
        ),
      );
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
    return zenPageScaffold(
      context: context,
      title: widget.existing == null ? '新建编排' : '编辑编排',
      actions: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: OutlinedButton(
            onPressed: _segments.isEmpty ? null : _save,
            style: zenButtonTheme(
              context,
              foreground: context.colors.accent,
              border: context.colors.accent,
            ),
            child: const Text('保存'),
          ),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtl,
            style: ZenText.body,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _descCtl,
            style: ZenText.body,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '描述',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 20),
          const Text('来源', style: ZenText.label),
          SizedBox(height: 8),
          Consumer<LabClockProvider>(
            builder: (context, provider, _) {
              if (provider.clocks.isEmpty) {
                return const Text('暂无时钟——先添加一个。', style: ZenText.label);
              }
              return SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: provider.clocks.length,
                  separatorBuilder: (_, _) => SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = provider.clocks[i];
                    final color = c.color == null
                        ? Theme.of(context).colorScheme.primary
                        : Color(int.parse(c.color!.replaceFirst('#', '0xFF')));
                    return InkWell(
                      onTap: () => _appendClock(c),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 120,
                        padding: EdgeInsets.all(8),
                        decoration: zenCardTheme(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    c.title,
                                    style: ZenText.body,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Spacer(),
                            Text(
                              formatDuration(c.durationSeconds ?? 0),
                              style: ZenText.monoDigitSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          SizedBox(height: 20),
          Text('序列', style: ZenText.label),
          SizedBox(height: 8),
          if (_segments.isEmpty)
            Container(
              padding: EdgeInsets.all(24),
              decoration: zenCardTheme(context),
              child: Center(child: Text('点上方时钟加入编排', style: ZenText.label)),
            )
          else
            ...List.generate(_segments.length, (i) {
              final seg = _segments[i];
              final color = seg.snapshotColor != null
                  ? Color(
                      int.parse(seg.snapshotColor!.replaceFirst('#', '0xFF')),
                    )
                  : context.colors.text;
              return Container(
                margin: EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: zenCardTheme(context),
                child: Row(
                  children: [
                    Text('${i + 1}', style: ZenText.monoDigitSmall),
                    SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(seg.snapshotTitle, style: ZenText.body),
                          if (seg.snapshotBpm != null)
                            Text(
                              '${seg.snapshotBpm}bpm ${seg.snapshotBeatPattern ?? ""}',
                              style: ZenText.monoDigitSmall,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      formatDuration(seg.snapshotDurationSeconds),
                      style: ZenText.monoDigitSmall,
                    ),
                    IconButton(
                      onPressed: i == 0 ? null : () => _moveUp(i),
                      icon: Icon(Icons.keyboard_arrow_up, size: 20),
                      tooltip: '上移',
                    ),
                    IconButton(
                      onPressed: i == _segments.length - 1
                          ? null
                          : () => _moveDown(i),
                      icon: Icon(Icons.keyboard_arrow_down, size: 20),
                      tooltip: '下移',
                    ),
                    IconButton(
                      onPressed: () => _removeSegment(i),
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: context.colors.danger,
                      ),
                      tooltip: '移除',
                    ),
                  ],
                ),
              );
            }),
          SizedBox(height: 16),
          ZenSection(
            title: '合计',
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              formatDuration(_totalSeconds),
              style: ZenText.monoDigit.copyWith(fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}
