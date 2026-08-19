import 'package:flutter/material.dart';
import '../../../widgets/context_colors.dart';

import 'const_recorder.dart';
import 'recorder_controller.dart';
import 'recorder_list_utils.dart';
import 'recording_file.dart';
import '../../../widgets/base/base_icon_button.dart';
import '../../../widgets/theme/zen_theme.dart';

/// 录音列表页 —— CRUD 的 Read/Update/Delete + 试听。
///
/// 由 [RecorderPageScaffold] 的 AppBar actions 按钮 push 进入。
/// 只依赖 [RecorderController] 的 list / rename / delete / play 接口,
/// 不持有录音状态机;离开时 [stopPlayback] 释放播放器。
class RecorderListPage extends StatefulWidget {
  final RecorderController controller;

  const RecorderListPage({super.key, required this.controller});

  @override
  State<RecorderListPage> createState() => _RecorderListPageState();
}

class _RecorderListPageState extends State<RecorderListPage> {
  List<RecordingFile>? _files; // null = loading

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    widget.controller.stopPlayback();
    super.dispose();
  }

  Future<void> _load() async {
    final files = await widget.controller.listRecordings();
    if (!mounted) return;
    setState(() => _files = files);
  }

  void _showError(String? msg) {
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _rename(RecordingFile f) async {
    final controller = TextEditingController(
      text: f.name.replaceFirst('.${RecorderConsts.fileExt}', ''),
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(RecorderUiText.renameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: RecorderUiText.renameHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(RecorderUiText.renameCancel),
          ),
          OutlinedButton(
            style: zenButtonTheme(context,
              foreground: context.colors.accent,
              border: context.colors.accent,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(RecorderUiText.renameOk),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null) return;
    final err = await widget.controller.renameRecording(f.path, newName);
    if (err != null) {
      _showError(err);
      return;
    }
    _load();
  }

  Future<void> _delete(RecordingFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(RecorderUiText.deleteTitle),
        content: Text(
          '${RecorderUiText.deleteConfirmPrefix}${f.name}'
          '${RecorderUiText.deleteConfirmSuffix}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(RecorderUiText.renameCancel),
          ),
          OutlinedButton(
            style: zenButtonTheme(context,
              foreground: context.colors.danger,
              border: context.colors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(RecorderUiText.deleteBtn),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await widget.controller.deleteRecording(f.path);
    if (!success) return;
    setState(() {
      if (_expandedPath == f.path) _expandedPath = null;
    });
    _load();
  }

  /// 当前展开的录音路径(单条展开;null = 全收起)。
  String? _expandedPath;

  /// 播放某条:先展开再播放(进度条立即可见)。playFile 自带 toggle。
  void _play(RecordingFile f) {
    setState(() => _expandedPath = f.path);
    widget.controller.playFile(f.path);
  }

  void _toggleExpand(RecordingFile f) {
    setState(() {
      _expandedPath = _expandedPath == f.path ? null : f.path;
    });
  }

  /// 当前排序(默认时间最新,与 listRecordings 默认一致)。
  RecordingSort _sort = RecordingSort.timeDesc;

  /// 是否按相对日期分组(今天/昨天/更早)。
  bool _groupByDay = false;

  static String _sortLabel(RecordingSort s) => switch (s) {
        RecordingSort.timeDesc => '时间·最新',
        RecordingSort.timeAsc => '时间·最旧',
        RecordingSort.nameAsc => '名称 A→Z',
        RecordingSort.nameDesc => '名称 Z→A',
        RecordingSort.sizeDesc => '大小·大→小',
        RecordingSort.sizeAsc => '大小·小→大',
      };

  /// 排序 + 分组 → 渲染项列表(tile / section 头)。
  List<Widget> _buildItems(List<RecordingFile> sorted) {
    Widget tile(RecordingFile f) => _RecordingTile(
          key: ValueKey(f.path),
          controller: widget.controller,
          file: f,
          expanded: _expandedPath == f.path,
          onToggleExpand: () => _toggleExpand(f),
          onPlay: () => _play(f),
          onRename: () => _rename(f),
          onDelete: () => _delete(f),
        );
    if (!_groupByDay) {
      return [for (final f in sorted) tile(f)];
    }
    final items = <Widget>[];
    for (final (label, group) in groupFilesByRelativeDay(sorted)) {
      items.add(_GroupHeader(label: label, count: group.length));
      items.addAll(group.map(tile));
    }
    return items;
  }

  Widget _buildListBranch(List<RecordingFile> files) {
    final items = _buildItems(sortFiles(files, _sort));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolRow(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(height: 8),
              itemBuilder: (context, index) => items[index],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolRow() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          InkWell(
            onTap: () => setState(() => _groupByDay = !_groupByDay),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _groupByDay
                        ? Icons.calendar_today
                        : Icons.calendar_today_outlined,
                    size: 16,
                    color: context.colors.accent,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '按日期',
                    style: ZenText.label.copyWith(color: context.colors.accent),
                  ),
                ],
              ),
            ),
          ),
          Spacer(),
          PopupMenuButton<RecordingSort>(
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (ctx) => [
              for (final s in RecordingSort.values)
                PopupMenuItem(value: s, child: Text(_sortLabel(s))),
            ],
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.swap_vert,
                      size: 16, color: context.colors.textMuted),
                  SizedBox(width: 4),
                  Text(_sortLabel(_sort), style: ZenText.label),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return zenPageScaffold(
      context: context,
  title: RecorderUiText.listTitle,
      actions: [
        IconButton(
          icon: Icon(Icons.refresh, color: context.colors.textMuted),
          tooltip: '刷新',
          onPressed: _load,
        ),
        SizedBox(width: 8),
      ],
      body: switch (files) {
        null => Center(child: CircularProgressIndicator(color: context.colors.accent)),
        _ when files.isEmpty => ZenEmptyState(
            icon: Icons.mic_none,
            message: RecorderUiText.emptyList,
            actionLabel: '刷新',
            onAction: _load,
          ),
        _ => _buildListBranch(files),
      },
    );
  }
}

/// 日期分组 section 头:标签 + 条数。
class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;

  const _GroupHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          Text(label, style: ZenText.label),
          SizedBox(width: 6),
          Text('($count)', style: ZenText.monoDigitSmall),
        ],
      ),
    );
  }
}

/// 单条录音 tile:收起态 = 元数据行;展开态 = 播放时间轴 + seek。
///
/// 播放态用 `AnimatedBuilder(controller)` 驱动(play/stop 时刷新,
/// 频率低);展开态时间轴用 `ValueListenableBuilder(playbackPosition)`
/// 订阅(≤250ms 更新,只 rebuild 该 tile 的时间轴 —— 性能隔离)。
class _RecordingTile extends StatefulWidget {
  final RecorderController controller;
  final RecordingFile file;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _RecordingTile({
    super.key,
    required this.controller,
    required this.file,
    required this.expanded,
    required this.onToggleExpand,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends State<_RecordingTile> {
  /// 拖动进度条中的临时位置(ms);null = 未拖动,跟随实际播放进度。
  double? _dragMs;

  bool _isPlaying() =>
      widget.controller.playingPath == widget.file.path &&
      widget.controller.isPlaying;

  String _durationLabel() {
    final d = widget.file.duration;
    return d == null ? '' : formatTime(d.inSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final playing = _isPlaying();
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: zenCardTheme(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, playing),
              if (widget.expanded) ...[
                Divider(color: context.colors.outline, height: 16),
                _buildTimeline(context),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool playing) {
    return InkWell(
      onTap: widget.onToggleExpand,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Icon(
            playing ? Icons.graphic_eq : Icons.audiotrack,
            color: playing ? context.colors.danger : context.colors.accent,
            size: 24,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZenText.body,
                ),
                Text(
                  [
                    if (_durationLabel().isNotEmpty) _durationLabel(),
                    widget.file.sizeLabel,
                    formatRecordDate(widget.file.displayTime),
                  ].join(' · '),
                  style: ZenText.monoDigitSmall,
                ),
              ],
            ),
          ),
          ZenIconButton(
            icon: playing ? Icons.stop_circle : Icons.play_circle,
            color: playing ? context.colors.danger : context.colors.accent,
            variant: BaseIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: widget.onPlay,
          ),
          SizedBox(width: 4),
          ZenIconButton(
            icon: Icons.edit_outlined,
            color: context.colors.textMuted,
            variant: BaseIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: widget.onRename,
          ),
          SizedBox(width: 4),
          ZenIconButton(
            icon: Icons.delete_outline,
            color: context.colors.danger,
            variant: BaseIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: widget.onDelete,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.playbackPosition,
      builder: (context, pos, _) {
        return ValueListenableBuilder<Duration?>(
          valueListenable: widget.controller.playbackDuration,
          builder: (context, total, _) {
            // 优先实测时长;未播放过则回落 bitrate 估算(见 RecordingFile.duration)。
            final effectiveTotal = total ?? widget.file.duration;
            final totalMs = effectiveTotal != null &&
                    effectiveTotal > Duration.zero
                ? effectiveTotal.inMilliseconds
                : null;
            final maxMs = totalMs?.toDouble() ?? 1.0;
            final value = (_dragMs ?? pos.inMilliseconds.toDouble())
                .clamp(0.0, maxMs)
                .toDouble();
            final canSeek = totalMs != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: context.colors.accent,
                    inactiveTrackColor: context.colors.outline,
                    thumbColor: context.colors.accent,
                    overlayColor: context.colors.accent.withValues(alpha: 0.1),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: value,
                    max: maxMs,
                    onChanged: canSeek
                        ? (v) => setState(() => _dragMs = v)
                        : null,
                    onChangeEnd: canSeek
                        ? (v) {
                            setState(() => _dragMs = null);
                            widget.controller
                                .seek(Duration(milliseconds: v.round()));
                          }
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatTime(pos.inSeconds),
                      style: ZenText.monoDigitSmall,
                    ),
                    Text(
                      effectiveTotal != null
                          ? formatTime(effectiveTotal.inSeconds)
                          : '--:--',
                      style: ZenText.monoDigitSmall,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
