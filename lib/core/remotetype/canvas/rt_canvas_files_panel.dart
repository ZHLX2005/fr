// lib/core/remotetype/canvas/rt_canvas_files_panel.dart
//
// 文件模块面板（v0.8.0+）：实时拍照直进电脑剪贴板；v0.9.0+ 加**上传文件**
// （任意文件 → PC 接收目录落盘 + CF_HDROP 复制，Ctrl+V 即粘贴文件）。
// 拍照（image_picker 系统相机，无新增依赖）与选文件（file_picker，仓库既有
// 依赖）都走同一条 RT1 分片加密上传通道（protocol/rt_image_transfer.dart，
// mime 区分图片/文件）。本面板只管「取材 → 发送 → 呈现」的编排与 UI。
//
// 动作区是两个**纯图标按钮**（拍照 / 上传都是习惯操作，不做颜色强调、
// 不加文字标签），色调用 onSurfaceVariant 融进画布，保持页面简洁。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/context/colors.dart';
import '../protocol/rt_image_transfer.dart';
import '../protocol/rt_session.dart';

/// 待发载荷的取材方式（决定完成文案与重试行为）。
enum _RtPayloadKind { photo, file }

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
  _RtPayloadKind _kind = _RtPayloadKind.photo;
  String? _fileName;
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
      await _startSend(
        bytes: bytes,
        kind: _RtPayloadKind.photo,
        fileName: null,
        photo: photo,
      );
    } catch (e) {
      widget.onNotify('拍照失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFile() async {
    if (_picking || !widget.connected || widget.session == null) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final file = result?.files.singleOrNull;
      if (file == null) return; // 用户取消选择
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        widget.onNotify('读不到文件内容，请重选');
        return;
      }
      await _startSend(
        bytes: bytes,
        kind: _RtPayloadKind.file,
        fileName: file.name,
      );
    } catch (e) {
      widget.onNotify('选择文件失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _startSend({
    required Uint8List bytes,
    required _RtPayloadKind kind,
    required String? fileName,
    XFile? photo,
  }) async {
    if (bytes.length > kRtImageMaxBytes) {
      widget.onNotify(
        '超过 10MB 上限，请换小一点的${kind == _RtPayloadKind.photo ? '分辨率重拍' : '文件'}',
      );
      return;
    }
    _transfer?.removeListener(_onTransferChanged);
    _transfer?.dispose();
    final transfer = RtImageTransfer(
      session: widget.session!,
      bytes: bytes,
      mime: kind == _RtPayloadKind.photo
          ? 'image/jpeg'
          : 'application/octet-stream',
      name: fileName,
    );
    transfer.addListener(_onTransferChanged);
    setState(() {
      // 拍照路径带预览图；文件路径传 null（预览区改显示文件名）
      _photo = photo;
      _bytes = bytes;
      _kind = kind;
      _fileName = fileName;
      _transfer = transfer;
    });
    await _runTransfer(transfer);
  }

  Future<void> _runTransfer(RtImageTransfer transfer) async {
    final ok = await transfer.send();
    if (!mounted) return;
    if (ok) {
      widget.onNotify(
        _kind == _RtPayloadKind.photo
            ? '图片已进电脑剪贴板，Ctrl+V 即可粘贴'
            : '文件已复制到电脑剪贴板，Ctrl+V 即可粘贴',
      );
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
    final transfer = RtImageTransfer(
      session: session,
      bytes: bytes,
      mime: _kind == _RtPayloadKind.photo
          ? 'image/jpeg'
          : 'application/octet-stream',
      name: _fileName,
    );
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
                  '拍照 / 文件 → 电脑剪贴板',
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
                Icon(
                  Icons.circle,
                  size: 10,
                  color: cs.primary.withValues(alpha: 0.6),
                )
              else
                Icon(Icons.circle, size: 10, color: cs.outline),
            ],
          ),
          if (widget.editMode)
            Expanded(
              child: Center(
                child: Text(
                  '拍照直进剪贴板 · 文件复制到电脑',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            if (busy) _progressBody(transfer!, cs),
            if (!busy) _previewOrActions(cs),
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
          LinearProgressIndicator(
            value: value,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
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

  /// 空闲 / 完成：预览区 + 拍照与上传两个图标按钮。
  Widget _previewOrActions(ColorScheme cs) {
    final photo = _photo;
    final canAct = widget.connected && !_picking && widget.session != null;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 4,
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
          else if (_kind == _RtPayloadKind.file && _fileName != null)
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    Flexible(
                      child: Text(
                        _fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Icon(
                  Icons.add_a_photo_outlined,
                  size: 30,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconAction(
                cs,
                icon: _picking && _kind == _RtPayloadKind.photo
                    ? null
                    : Icons.photo_camera_outlined,
                busyIcon: _picking && _kind == _RtPayloadKind.photo,
                tooltip: widget.connected ? '拍照并发送' : '未连接电脑',
                onPressed: (_picking && _kind == _RtPayloadKind.photo) || !canAct
                    ? null
                    : _takePhoto,
              ),
              const SizedBox(width: 20),
              _iconAction(
                cs,
                icon: _picking && _kind == _RtPayloadKind.file
                    ? null
                    : Icons.upload_file_outlined,
                busyIcon: _picking && _kind == _RtPayloadKind.file,
                tooltip: widget.connected ? '上传文件' : '未连接电脑',
                onPressed: (_picking && _kind == _RtPayloadKind.file) || !canAct
                    ? null
                    : _pickFile,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 图标动作按钮：弱化色调（onSurfaceVariant）融进画布，禁用再降透明度。
  Widget _iconAction(
    ColorScheme cs, {
    required IconData? icon,
    required bool busyIcon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: busyIcon
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onSurfaceVariant,
              ),
            )
          : Icon(icon, size: 24),
      color: cs.onSurfaceVariant,
      disabledColor: cs.onSurfaceVariant.withValues(alpha: 0.35),
      visualDensity: VisualDensity.compact,
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
