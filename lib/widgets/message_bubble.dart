import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../models/models.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final User? sender;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.sender,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  String? _currentlyPlayingPath;

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final difference = now.difference(widget.message.createdAt);

    String timeText;
    if (difference.inMinutes < 1) {
      timeText = '刚刚';
    } else if (difference.inHours < 1) {
      timeText = '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      timeText = DateFormat('HH:mm').format(widget.message.createdAt);
    } else {
      timeText = DateFormat('MM/dd HH:mm').format(widget.message.createdAt);
    }

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Column(
          crossAxisAlignment:
              widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!widget.isMe && widget.sender != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 12),
                child: Text(
                  widget.sender!.nickname,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isMe && widget.sender?.avatar != null)
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(widget.sender!.avatar!),
                  ),
                if (!widget.isMe) const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isMe
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      gradient: widget.isMe
                          ? LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.primary.withOpacity(0.8),
                              ],
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMessageContent(context, theme),
                        const SizedBox(height: 4),
                        Text(
                          timeText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: widget.isMe
                                ? theme.colorScheme.onPrimary.withOpacity(0.7)
                                : theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _buildStatusIcon(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme) {
    if (!widget.isMe) return const SizedBox.shrink();

    switch (widget.message.status) {
      case MessageStatus.sending:
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        );
      case MessageStatus.sent:
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            Icons.done,
            size: 16,
            color: theme.colorScheme.onSurface.withOpacity(0.4),
          ),
        );
      case MessageStatus.read:
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            Icons.done_all,
            size: 16,
            color: theme.colorScheme.primary,
          ),
        );
      case MessageStatus.failed:
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
        );
    }
  }

  Widget _buildMessageContent(BuildContext context, ThemeData theme) {
    switch (widget.message.type) {
      case MessageType.image:
        return _buildImageMessage(context, theme);
      case MessageType.video:
        return _buildVideoMessage(context, theme);
      case MessageType.audio:
        return _buildAudioMessage(context, theme);
      case MessageType.file:
        return _buildFileMessage(context, theme);
      case MessageType.text:
      case MessageType.system:
        return Text(
          widget.message.content,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: widget.isMe
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        );
    }
  }

  Widget _buildImageMessage(BuildContext context, ThemeData theme) {
    final filePath = widget.message.content;

    return GestureDetector(
      onTap: () => _showImageViewer(context, filePath),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: kIsWeb
            ? (filePath.startsWith('data:') == true
                ? Image.network(
                    filePath,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildImageError(theme);
                    },
                  )
                : Image.file(
                    File(filePath),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildImageError(theme);
                    },
                  ))
            : Image.file(
                File(filePath),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildImageError(theme);
                },
              ),
      ),
    );
  }

  void _showImageViewer(BuildContext context, String filePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageViewerPage(filePath: filePath),
      ),
    );
  }

  Widget _buildImageError(ThemeData theme) {
    return Container(
      width: 200,
      height: 200,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image,
            size: 48,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(height: 8),
          Text(
            '图片加载失败',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoMessage(BuildContext context, ThemeData theme) {
    return GestureDetector(
      onTap: () => _showVideoPlayer(context),
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 视频封面（如果有本地文件，显示第一帧）
            if (kIsWeb)
              const Icon(Icons.videocam, size: 48, color: Colors.white70)
            else
              Image.file(
                File(widget.message.content),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.videocam, size: 48, color: Colors.white70);
                },
              ),
            const Icon(
              Icons.play_circle_filled,
              color: Colors.white70,
              size: 48,
            ),
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '视频消息',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoPlayer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _VideoPlayerPage(videoPath: widget.message.content),
      ),
    );
  }

  Widget _buildAudioMessage(BuildContext context, ThemeData theme) {
    // 检查当前是否正在播放这条语音
    final isCurrentPlaying = _isPlaying && _currentlyPlayingPath == widget.message.content;

    return GestureDetector(
      onTap: () => _playAudio(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isMe
              ? theme.colorScheme.primary.withOpacity(0.2)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCurrentPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: widget.isMe
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 8),
            // 模拟音频波形
            _buildAudioWave(theme),
            const SizedBox(width: 8),
            Text(
              '语音',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: widget.isMe
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playAudio(BuildContext context) async {
    try {
      // 检查文件是否存在
      final file = File(widget.message.content);
      if (!file.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('音频文件不存在')),
          );
        }
        return;
      }

      _audioPlayer ??= AudioPlayer();

      // 如果当前正在播放这条语音，暂停它
      if (_isPlaying && _currentlyPlayingPath == widget.message.content) {
        await _audioPlayer!.pause();
        setState(() {
          _currentlyPlayingPath = null;
        });
        return;
      }

      // 设置当前播放路径并播放
      setState(() {
        _currentlyPlayingPath = widget.message.content;
      });

      await _audioPlayer!.play(DeviceFileSource(widget.message.content));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放中: ${widget.message.content.split('/').last}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('播放音频失败: $e');
      setState(() {
        _currentlyPlayingPath = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  Widget _buildAudioWave(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Container(
          width: 3,
          height: 12 + (index * 4).toDouble() % 12,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: (widget.isMe
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary)
                .withOpacity(0.6),
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }

  Widget _buildFileMessage(BuildContext context, ThemeData theme) {
    final fileName = widget.message.content.split('/').last;

    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: widget.isMe
            ? theme.colorScheme.primary.withOpacity(0.2)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(fileName),
            color: widget.isMe
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widget.isMe
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  '文件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: (widget.isMe
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface)
                        .withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      case 'aac':
        return Icons.music_note;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
        return Icons.video_library;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}

/// 图片查看器页面
class _ImageViewerPage extends StatelessWidget {
  final String filePath;

  const _ImageViewerPage({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: kIsWeb
              ? (filePath.startsWith('data:')
                  ? Image.network(filePath)
                  : Image.file(File(filePath)))
              : Image.file(File(filePath)),
        ),
      ),
    );
  }
}

/// 视频播放器页面
class _VideoPlayerPage extends StatefulWidget {
  final String videoPath;

  const _VideoPlayerPage({required this.videoPath});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.file(File(widget.videoPath));
      await _videoController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
      );
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('视频播放', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: _errorMessage != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    '视频加载失败',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : _isInitialized && _chewieController != null
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
