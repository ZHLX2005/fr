import 'package:flutter/material.dart';

/// 发送消息对话框。
///
/// 纯前端 mock：消息存于内存，关闭即丢弃。
/// 后续接入后端后替换实际发送逻辑。
class MessageDialog extends StatefulWidget {
  /// 当前 block 的序列化 JSON。
  final Map<String, dynamic> serializedBlock;

  /// 引用数据：Block 的完整序列化 JSON，含 originalBlockId 在 properties 中。
  final Map<String, dynamic>? quoteData;

  const MessageDialog({
    super.key,
    required this.serializedBlock,
    this.quoteData,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> serializedBlock,
    Map<String, dynamic>? quoteData,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MessageDialog(
        serializedBlock: serializedBlock,
        quoteData: quoteData,
      ),
    );
  }

  @override
  State<MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<MessageDialog> {
  final _messages = <Map<String, dynamic>>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  Map<String, dynamic>? _pendingQuote;

  @override
  void initState() {
    super.initState();
    _pendingQuote = widget.quoteData;
    if (widget.quoteData != null) {
      _messages.add({
        'block': widget.serializedBlock,
        'quote': widget.quoteData,
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'block': widget.serializedBlock,
        'content': text,
        'quote': _pendingQuote,
      });
      _pendingQuote = null;
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('发送消息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 消息列表
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('暂无消息', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isQuote = msg['content'] == null || (msg['content'] as String).isEmpty;
                      return _MessageItem(
                        content: msg['content'] as String? ?? '',
                        quoteBlock: msg['quote'] as Map<String, dynamic>?,
                        isQuoteOnly: isQuote,
                      );
                    },
                  ),
          ),
          // 输入区域
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                    color: Colors.blue,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final String content;
  final Map<String, dynamic>? quoteBlock;
  final bool isQuoteOnly;

  const _MessageItem({
    required this.content,
    this.quoteBlock,
    this.isQuoteOnly = false,
  });

  String get _quoteText {
    if (quoteBlock == null) return '';
    final c = quoteBlock!['content'] as Map<String, dynamic>?;
    if (c == null) return '';
    final spans = c['spans'] as List<dynamic>?;
    if (spans == null) return '';
    return spans
        .map((s) => (s as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final quoteText = _quoteText;
    final hasContent = content.isNotEmpty;

    return Container(
      width: double.maxFinite,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quoteText.isNotEmpty)
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: Colors.blue[300]!, width: 3),
                ),
              ),
              child: Text(
                quoteText,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (quoteText.isNotEmpty && hasContent)
            const SizedBox(height: 4),
          if (hasContent)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue[500],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(4),
                  ),
                ),
                child: Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
