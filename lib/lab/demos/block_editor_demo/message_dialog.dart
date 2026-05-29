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

  @override
  void initState() {
    super.initState();
    // 如果有引用数据，作为首条消息显示
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
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'block': widget.serializedBlock,
        'content': text,
        'quote': widget.quoteData,
      });
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 32, height: 3,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('发送消息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('暂无消息', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _MessageItem(
                        content: msg['content'] as String? ?? '',
                        quoteBlock: msg['quote'] as Map<String, dynamic>?,
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
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

  const _MessageItem({
    required this.content,
    this.quoteBlock,
  });

  String get _quoteText {
    if (quoteBlock == null) return '';
    final content = quoteBlock!['content'] as Map<String, dynamic>?;
    if (content == null) return '';
    final spans = content['spans'] as List<dynamic>?;
    if (spans == null) return '';
    return spans
        .map((s) => (s as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final quoteText = _quoteText;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quoteText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
                border: Border(
                  left: BorderSide(color: Colors.grey[400]!, width: 3),
                ),
              ),
              child: Text(
                quoteText,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          Text(
            content,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
