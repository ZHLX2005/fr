// lib/core/remotetype/canvas/rt_canvas_files_panel.dart
//
// 文件模块面板（v0.8.0+）：第一个能力 = 实时拍照直进电脑剪贴板。
// 拍照（image_picker 系统相机，无新增依赖）→ RT1 分片加密上传 → PC 写剪贴板
// → Ctrl+V 即贴。分片 / 续传 / 进度逻辑全在 protocol/rt_image_transfer.dart，
// 本面板只管「拍照 → 发送 → 呈现」的编排与 UI。
//
// 后续文件类能力（相册选图 / 任意文件）都在本面板下加入口，共用同一传输层。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/context/colors.dart';
import '../protocol/rt_image_transfer.dart';
import '../protocol/rt_session.dart';

/// 文件模块面板。session 为空（未配对）时整板置灰，只做占位说明。
class RtFilesPanel extends StatefulWidget {
  const RtFilesPanel({
    super.key,
    required this.session,
    required this.connected,
    required this.editMode,
    required this.onNotify,
  });

  final RtSession? session;
  final bool connected;
  final bool editMode;
  final void Function(String message) onNotify;

  @override
  State<RtFilesPanel> createState() => _RtFilesPanelState();
}

class _RtFilesPanelState extends State<RtFilesPanel> {
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;
  Uint8List? _bytes;
  RtImageTransfer? _transfer;
  bool _picking = false;

  @override
  void dispose() {
    _transfer?.removeListener(_onTransferChanged);
    _transfer?.dispose();
    super.dispose();
  }

  void _onTransferChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    if (_picking || !widget.connected || widget.session == null) return;
    setState(() => _picking = true);
    try {
      // 系统相机出片：2560px / q90 ≈ 1-2MB，Exif 方向已由 picker 烘平，
      // PC 端拿到的是正立 JPEG。10MB 上限内足够任何粘贴场景。
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 90,
      );
      if (photo == null) return; // 用户取消拍照
      final bytes = await photo.readAsBytes();
      if (bytes.length > kRtImageMaxBytes) {
        widget.onNotify('照片超过 10MB 上限，请用较低分辨率重拍');
        return;
      }
      _transfer?.removeListener(_onTransferChanged);
      _transfer?.dispose();
      final transfer = RtImageTransfer(
        session: widget.session!,
        bytes: bytes,
      );
      transfer.addListener(_onTransferChanged);
      setState(() {
        _photo = photo;
        _bytes = bytes;
        _transfer = transfer;
      });
      unawaited(_runTransfer(transfer));
    } catch (e) {
      widget.onNotify('拍照失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _runTransfer(RtImageTransfer transfer) async {
    final ok = await transfer.send();
    if (!mounted) return;
    if (ok) {
      widget.onNotify('图片已进电脑剪贴板，Ctrl+V 即可粘贴');
    } else if (transfer.error != null && transfer.error != '已取消') {
      widget.onNotify('传输失败：${transfer.error}');
    }
    setState(() {});
  }

  /// 重试 = 新任务（新 id）：手机端跨任务不保对账状态，PC 端旧半成品按
  /// 保留期自然过期，宁可整图重发也不对不上的账。
  void _retry() {
    final bytes = _bytes;
    final session = widget.session;
    if (bytes == null || session == null) return;
    _transfer?.removeListener(_onTransferChanged);
    _transfer?.dispose();
    final transfer = RtImageTransfer(session: session, bytes: bytes);
    transfer.addListener(_onTransferChanged);
    setState(() => _transfer = transfer);
    unawaited(_runTransfer(transfer));
  }

  Future<void> _cancel() async {
    await _transfer?.abort();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    final transfer = _transfer;
    final busy = transfer?.busy ?? false;
    final done = transfer?.phase == RtImagePhase.done;
    final failed = transfer?.phase == RtImagePhase.failed;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '拍照 → 电脑剪贴板',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (done)
                Icon(Icons.check_circle, size: 18, color: cs.primary)
              else if (widget.connected)
                Icon(Icons.circle, size: 10, color: cs.primary.withValues(alpha: 0.6))
              else
                Icon(Icons.circle, size: 10, color: cs.outline),
            ],
          ),
          if (widget.editMode)
            Expanded(
              child: Center(
                child: Text(
                  '拍一张照片，直进电脑剪贴板',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            if (busy) _progressBody(transfer!, cs),
            if (!busy) _previewOrButton(cs),
            if (failed && transfer != null) _errorRow(transfer, cs),
          ],
        ],
      ),
    );
  }

  /// 传输中：进度条 + 计数 + 取消。
  Widget _progressBody(RtImageTransfer transfer, ColorScheme cs) {
    final value = transfer.totalChunks == 0
        ? null
        : (transfer.ackedChunks / transfer.totalChunks).clamp(0.0, 1.0);
    final stage = switch (transfer.phase) {
      RtImagePhase.sending => '发送分片',
      RtImagePhase.waitingConfirm => '等待电脑确认',
      RtImagePhase.resending => '补发缺失分片',
      _ => '传输中',
    };
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          LinearProgressIndicator(value: value, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          Text(
            '$stage ${transfer.ackedChunks}/${transfer.totalChunks} 块',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          TextButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 空闲 / 完成：预览图 + 拍照按钮。
  Widget _previewOrButton(ColorScheme cs) {
    final photo = _photo;
    final canShoot = widget.connected && !_picking;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          if (photo != null)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(photo.path),
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Icon(
                  Icons.add_a_photo_outlined,
                  size: 34,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: canShoot ? _takePhoto : null,
            icon: _picking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera, size: 18),
            label: Text(
              _picking ? '相机启动中' : (widget.connected ? '拍照并发送' : '未连接电脑'),
            ),
          ),
        ],
      ),
    );
  }

  /// 失败：原因 + 重试。
  Widget _errorRow(RtImageTransfer transfer, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: Text(
            transfer.error ?? '传输失败',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.error),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重试'),
        ),
      ],
    );
  }
}
