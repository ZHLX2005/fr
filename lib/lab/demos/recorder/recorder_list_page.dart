import 'dart:io';

import 'package:flutter/material.dart';

import 'const_recorder.dart';
import 'recorder_controller.dart';
import '../../../core/design/emphasis_button.dart';

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
            style: EmphasisButton.borderEmphasis(
              ctx,
              color: Theme.of(ctx).colorScheme.primary,
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
            style: EmphasisButton.dangerEmphasis(ctx),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(RecorderUiText.listTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: switch (files) {
        null => const Center(child: CircularProgressIndicator()),
        _ when files.isEmpty => _EmptyState(onRefresh: _load),
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

/// 空列表状态(允许下拉刷新)。
class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Icon(Icons.mic_off, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          Center(
            child: Text(
              RecorderUiText.emptyList,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
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

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          playing ? Icons.graphic_eq : Icons.audiotrack,
          color: playing ? Colors.redAccent : null,
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${file.sizeKb.toStringAsFixed(1)} KB · ${_fmtDate(file.lastModified)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: playing ? RecorderUiText.stopPlay : RecorderUiText.play,
              icon: Icon(playing ? Icons.stop_circle : Icons.play_circle),
              color: playing ? Colors.redAccent : Colors.green,
              onPressed: onPlay,
            ),
            IconButton(
              tooltip: RecorderUiText.rename,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onRename,
            ),
            IconButton(
              tooltip: RecorderUiText.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}