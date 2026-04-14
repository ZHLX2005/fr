import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'emoji_picker_widget.dart';
import 'message_preview.dart';
import '../models/message.dart';
import '../services/media_service.dart';
import '../services/audio_recording_service.dart';

class ChatInputField extends StatefulWidget {
  final Function(String content) onSend;
  final Function(String? filePath, {MessageType type})? onImageSend;
  final bool isLoading;
  final String hintText;
  final int maxLines;
  final TextEditingController? controller;

  const ChatInputField({
    super.key,
    required this.onSend,
    this.onImageSend,
    this.isLoading = false,
    this.hintText = '输入消息...',
    this.maxLines = 5,
    this.controller,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  late TextEditingController _controller;
  bool _isComposing = false;
  bool _showEmojiPicker = false;

  // 录音相关
  final AudioRecordingService _audioService = AudioRecordingService();
  bool _isRecording = false;

  // 预览相关
  List<PreviewMessage> _previews = [];

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    _audioService.cancelRecording();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _isComposing = _controller.text.trim().isNotEmpty;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;

    widget.onSend(text);
    _controller.clear();
    setState(() {
      _isComposing = false;
    });
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
  }

  void _onEmojiSelected(String emoji) {
    final text = _controller.text;
    final cursorPosition = _controller.selection.baseOffset;
    final newText =
        text.substring(0, cursorPosition) +
        emoji +
        text.substring(cursorPosition);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPosition + emoji.length),
    );

    HapticFeedback.lightImpact();
  }

  // 添加预览
  void _addPreview(PreviewMessage preview) {
    setState(() {
      _previews.add(preview);
    });
  }

  // 移除预览
  void _removePreview(int index) {
    setState(() {
      _previews.removeAt(index);
    });
  }

  // 发送预览内容
  Future<void> _sendPreview(int index) async {
    final preview = _previews[index];
    switch (preview.type) {
      case PreviewType.text:
        widget.onSend(preview.content);
        _controller.text = preview.content;
        break;
      case PreviewType.image:
        await widget.onImageSend?.call(
          preview.filePath,
          type: MessageType.image,
        );
        break;
      case PreviewType.video:
        await widget.onImageSend?.call(
          preview.filePath,
          type: MessageType.video,
        );
        break;
      case PreviewType.audio:
        await widget.onImageSend?.call(
          preview.filePath,
          type: MessageType.audio,
        );
        break;
      case PreviewType.file:
        await widget.onImageSend?.call(
          preview.filePath,
          type: MessageType.file,
        );
        break;
    }
    _removePreview(index);
  }

  Future<void> _showAttachmentOptions() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAttachmentSheet(),
    );
  }

  Widget _buildAttachmentSheet() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              childAspectRatio: 0.9,
              children: [
                _buildAttachmentItem(
                  icon: Icons.photo_library,
                  label: '相册',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    _pickImageFromGallery();
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.camera_alt,
                  label: '拍照',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    _takePicture();
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.videocam,
                  label: '视频',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideo();
                  },
                ),
                _buildAttachmentItem(
                  icon: Icons.attach_file,
                  label: '文件',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    final imagePath = await MediaService.pickImageFromGallery();
    if (imagePath != null) {
      _addPreview(
        PreviewMessage(
          type: PreviewType.image,
          content: '图片',
          filePath: imagePath,
        ),
      );
    }
  }

  Future<void> _takePicture() async {
    final imagePath = await MediaService.takePicture();
    if (imagePath != null) {
      _addPreview(
        PreviewMessage(
          type: PreviewType.image,
          content: '照片',
          filePath: imagePath,
        ),
      );
    }
  }

  Future<void> _pickVideo() async {
    final videoPath = await MediaService.pickVideoFromGallery();
    if (videoPath != null) {
      // 获取文件信息
      String fileName = videoPath.split('/').last;
      int fileSize = 0;
      if (!kIsWeb) {
        final file = File(videoPath);
        if (file.existsSync()) {
          fileSize = file.lengthSync();
        }
      }

      _addPreview(
        PreviewMessage(
          type: PreviewType.video,
          content: '视频',
          filePath: videoPath,
          fileName: fileName,
          fileSize: fileSize,
        ),
      );
    }
  }

  Future<void> _pickFile() async {
    final result = await MediaService.pickFile();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;

      // 如果是图片，作为图片预览
      if (file.extension?.toLowerCase() == 'png' ||
          file.extension?.toLowerCase() == 'jpg' ||
          file.extension?.toLowerCase() == 'jpeg' ||
          file.extension?.toLowerCase() == 'gif') {
        if (file.path != null) {
          _addPreview(
            PreviewMessage(
              type: PreviewType.image,
              content: '图片',
              filePath: file.path,
              fileName: file.name,
              fileSize: file.size,
            ),
          );
        }
      } else {
        // 其他文件
        _addPreview(
          PreviewMessage(
            type: PreviewType.file,
            content: '文件',
            filePath: file.path,
            fileName: file.name,
            fileSize: file.size,
          ),
        );
      }
    }
  }

  // 录音功能
  Future<void> _handleAudioRecording() async {
    if (_isRecording) {
      // 停止录音，获取时长
      final (path, durationSeconds) = await _audioService
          .stopRecordingWithDuration();
      if (path != null) {
        final duration = Duration(seconds: durationSeconds);
        _addPreview(
          PreviewMessage(
            type: PreviewType.audio,
            content: '语音',
            filePath: path,
            duration: duration,
          ),
        );
      }
      setState(() {
        _isRecording = false;
      });
      return;
    }

    // 开始录音
    final success = await _audioService.startRecording();
    if (success && mounted) {
      setState(() {
        _isRecording = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('开始录音...'),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('录音启动失败，请检查麦克风权限')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // 预览区域
        if (_previews.isNotEmpty)
          Container(
            height: 120,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _previews.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 100,
                          child: MessagePreviewWidget(
                            preview: _previews[index],
                            onRemove: () => _removePreview(index),
                            onSend: () => _sendPreview(index),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // 语音录制状态提示
        if (_isRecording)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('正在录音...', style: TextStyle(color: Colors.red)),
                IconButton(
                  icon: const Icon(Icons.stop, color: Colors.red),
                  iconSize: 20,
                  onPressed: _handleAudioRecording,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        if (_showEmojiPicker)
          InlineEmojiPicker(onEmojiSelected: _onEmojiSelected),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      size: 28,
                    ),
                    onPressed: _showAttachmentOptions,
                  ),

                  // Text input field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _controller,
                        maxLines: widget.maxLines,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _handleSend(),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Emoji button
                  IconButton(
                    icon: Icon(
                      _showEmojiPicker
                          ? Icons.keyboard
                          : Icons.emoji_emotions_outlined,
                      color: _showEmojiPicker
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                      size: 24,
                    ),
                    onPressed: _toggleEmojiPicker,
                  ),

                  // Voice record button
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording
                          ? Colors.red
                          : (theme.colorScheme.onSurface.withOpacity(0.6)),
                      size: 24,
                    ),
                    onPressed: _handleAudioRecording,
                  ),

                  // Send button
                  IconButton(
                    icon: widget.isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            _isComposing ? Icons.send : Icons.mic_none,
                            color: _isComposing
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withOpacity(0.6),
                            size: 24,
                          ),
                    onPressed: _isComposing && !widget.isLoading
                        ? _handleSend
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
