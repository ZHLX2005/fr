import 'package:flutter/material.dart';

import 'const_recorder.dart';
import 'recorder_controller.dart';
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
  String? _error;

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
    setState(() => _error = null);
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
        title: const Text(RecorderUiText.renameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: RecorderUiText.renameHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(RecorderUiText.renameCancel),
          ),
          OutlinedButton(
            style: zenButton(
              foreground: ZenColors.sage,
              border: ZenColors.sage,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(RecorderUiText.renameOk),
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
        title: const Text(RecorderUiText.deleteTitle),
        content: Text(
          '${RecorderUiText.deleteConfirmPrefix}${f.name}'
          '${RecorderUiText.deleteConfirmSuffix}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(RecorderUiText.renameCancel),
          ),
          OutlinedButton(
            style: zenButton(
              foreground: ZenColors.mutedRed,
              border: ZenColors.mutedRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(RecorderUiText.deleteBtn),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await widget.controller.deleteRecording(f.path);
    if (!success) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return zenPageScaffold(
      title: RecorderUiText.listTitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: ZenColors.secondary),
          tooltip: '刷新',
          onPressed: _load,
        ),
        const SizedBox(width: 8),
      ],
      body: switch (files) {
        null => const Center(child: CircularProgressIndicator(color: ZenColors.sage)),
        _ when files.isEmpty => ZenEmptyState(
            icon: Icons.mic_none,
            message: RecorderUiText.emptyList,
            actionLabel: '刷新',
            onAction: _load,
          ),
        _ => RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: files.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final f = files[index];
                return _RecordingTile(
                  file: f,
                  playing: widget.controller.playingPath == f.path,
                  onPlay: () => widget.controller.playFile(f.path),
                  onRename: () => _rename(f),
                  onDelete: () => _delete(f),
                );
              },
            ),
          ),
      },
    );
  }
}

/// 单条录音 tile:文件名 + 大小 + 播放/重命名/删除。
class _RecordingTile extends StatelessWidget {
  final RecordingFile file;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _RecordingTile({
    required this.file,
    required this.playing,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: zenCard(),
      child: Row(
        children: [
          Icon(
            playing ? Icons.graphic_eq : Icons.audiotrack,
            color: playing ? ZenColors.mutedRed : ZenColors.sage,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZenText.body,
                ),
                Text(
                  '${file.sizeKb.toStringAsFixed(1)} KB · ${formatRecordDate(file.lastModified)}',
                  style: ZenText.monoDigitSmall,
                ),
              ],
            ),
          ),
          ZenIconButton(
            icon: playing ? Icons.stop_circle : Icons.play_circle,
            color: playing ? ZenColors.mutedRed : ZenColors.sage,
            variant: ZenIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: onPlay,
          ),
          const SizedBox(width: 4),
          ZenIconButton(
            icon: Icons.edit_outlined,
            color: ZenColors.secondary,
            variant: ZenIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: onRename,
          ),
          const SizedBox(width: 4),
          ZenIconButton(
            icon: Icons.delete_outline,
            color: ZenColors.mutedRed,
            variant: ZenIconButtonVariant.tint,
            size: 40,
            iconSize: 20,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}
