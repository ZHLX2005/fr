import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/emoji_picker_widget.dart';
import '../services/media_service.dart';
import '../services/speech_input_service.dart';

class ChatInputField extends StatefulWidget {
  final Function(String content) onSend;
  final Function(String? imagePath)? onImageSend;
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

  // 语音输入相关
  final SpeechInputService _speechService = SpeechInputService();
  bool _isListening = false;
  String _speechStatus = '点击说话';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);

    // 初始化语音识别
    _speechService.initialize().then((available) {
      if (available && mounted) {
        setState(() {
          _speechStatus = '点击说话';
        });
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    _speechService.dispose();
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
    final newText = text.substring(0, cursorPosition) +
        emoji +
        text.substring(cursorPosition);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: cursorPosition + emoji.length,
      ),
    );

    HapticFeedback.lightImpact();
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
              mainAxisSpacing: 16,
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    final imagePath = await MediaService.pickImageFromGallery();
    if (imagePath != null) {
      widget.onImageSend?.call(imagePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已选择')),
        );
      }
    }
  }

  Future<void> _takePicture() async {
    final imagePath = await MediaService.takePicture();
    if (imagePath != null) {
      widget.onImageSend?.call(imagePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('照片已拍摄')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    final videoPath = await MediaService.pickVideoFromGallery();
    if (videoPath != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频已选择: $videoPath')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await MediaService.pickFile();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件已选择: ${file.name}')),
        );
      }
    }
  }

  // 语音输入处理
  Future<void> _handleSpeechInput() async {
    if (_isListening) {
      // 停止监听
      await _speechService.stopListening();
      setState(() {
        _isListening = false;
        _speechStatus = '点击说话';
      });
      return;
    }

    // 开始监听
    final success = await _speechService.startListening(
      onResult: (text) {
        setState(() {
          _speechStatus = '识别中...';
        });
      },
      onListeningStateChanged: (state) {
        if (mounted) {
          setState(() {
            switch (state) {
              case 'listening':
                _isListening = true;
                _speechStatus = '正在聆听...';
                break;
              case 'stopped':
                _isListening = false;
                _speechStatus = '点击说话';
                break;
              case 'error':
                _isListening = false;
                _speechStatus = '点击重试';
                break;
            }
          });
        }
      },
    );

    if (!success && mounted) {
      setState(() {
        _speechStatus = '点击重试';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音识别启动失败，请检查麦克风权限')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        if (_showEmojiPicker)
          InlineEmojiPicker(
            onEmojiSelected: _onEmojiSelected,
          ),
        // 识别状态提示
        if (_isListening)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _speechStatus,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
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

                  // Voice input button
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.stop : Icons.mic,
                      color: _isListening
                          ? Colors.red
                          : (_speechStatus == '点击重试'
                              ? Colors.orange
                              : theme.colorScheme.onSurface.withOpacity(0.6)),
                      size: 24,
                    ),
                    onPressed: _handleSpeechInput,
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
                    onPressed: _isComposing && !widget.isLoading ? _handleSend : null,
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
