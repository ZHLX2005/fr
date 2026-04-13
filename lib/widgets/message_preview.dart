import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 预览消息类型
enum PreviewType {
  text,
  image,
  video,
  audio,
  file,
}

/// 预览消息数据
class PreviewMessage {
  final PreviewType type;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final Duration? duration;

  PreviewMessage({
    required this.type,
    required this.content,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.duration,
  });

  bool get isMedia => type != PreviewType.text && type != PreviewType.file;
}

/// 消息预览组件
class MessagePreviewWidget extends StatelessWidget {
  final PreviewMessage preview;
  final VoidCallback onRemove;
  final VoidCallback onSend;

  const MessagePreviewWidget({
    super.key,
    required this.preview,
    required this.onRemove,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 100,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 预览内容
          SizedBox(
            width: 88,
            height: 56,
            child: _buildPreviewContent(context),
          ),
          const SizedBox(height: 4),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              InkWell(
                onTap: onSend,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.send,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent(BuildContext context) {
    switch (preview.type) {
      case PreviewType.image:
        return _buildImagePreview(context);
      case PreviewType.video:
        return _buildVideoPreview(context);
      case PreviewType.audio:
        return _buildAudioPreview(context);
      case PreviewType.file:
        return _buildFilePreview(context);
      case PreviewType.text:
        return _buildTextPreview(context);
    }
  }

  Widget _buildImagePreview(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: kIsWeb
          ? (preview.filePath?.startsWith('data:') == true
              ? Image.network(
                  preview.filePath!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildErrorPlaceholder();
                  },
                )
              : Image.file(
                  File(preview.filePath!),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildErrorPlaceholder();
                  },
                ))
          : Image.file(
              File(preview.filePath!),
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorPlaceholder();
              },
            ),
    );
  }

  Widget _buildVideoPreview(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (preview.filePath != null)
            Image.file(
              File(preview.filePath!),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.videocam, size: 48, color: Colors.white);
              },
            )
          else
            const Icon(Icons.videocam, size: 48, color: Colors.white),
          const Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Text(
              '视频文件',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const Positioned(
            top: 8,
            right: 8,
            child: Icon(Icons.play_circle_filled,
                color: Colors.white70, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPreview(BuildContext context) {
    final theme = Theme.of(context);
    final duration = preview.duration ?? const Duration(seconds: 0);
    final durationText = duration.inSeconds > 0
        ? '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : '${duration.inSeconds}s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 6),
          Text(
            durationText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePreview(BuildContext context) {
    final theme = Theme.of(context);
    final size = preview.fileSize ?? 0;
    final sizeText = size > 0
        ? size > 1024 * 1024
            ? '${(size / (1024 * 1024)).toStringAsFixed(1)}MB'
            : '${(size / 1024).toStringAsFixed(1)}KB'
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(preview.fileName ?? ''),
            color: theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  preview.fileName ?? '未知文件',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sizeText.isNotEmpty)
                Text(
                  sizeText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextPreview(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        preview.content,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('加载失败', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
        return Icons.archive;
      case 'txt':
        return Icons.text_snippet;
      case 'mp3':
      case 'wav':
        return Icons.music_note;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_library;
      default:
        return Icons.insert_drive_file;
    }
  }
}
