import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/widgets.dart';

class ChatDetailPage extends StatefulWidget {
  final User friend;

  const ChatDetailPage({super.key, required this.friend});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final ScrollController _scrollController = ScrollController();
  late MessageProvider _messageProvider;

  @override
  void initState() {
    super.initState();
    _messageProvider = context.read<MessageProvider>();
    _loadMessages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser!;

    await _messageProvider.loadChatMessages(currentUser.id, widget.friend.id);
    await _messageProvider.markAsRead(widget.friend.id, currentUser.id);

    // Scroll to bottom
    if (_scrollController.hasClients) {
      await Future.delayed(const Duration(milliseconds: 100));
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSend(String content) async {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser!;
    final sessionProvider = context.read<ChatSessionProvider>();

    await _messageProvider.sendMessage(
      senderId: currentUser.id,
      receiverId: widget.friend.id,
      content: content,
    );

    // Update session and scroll to bottom
    await sessionProvider.refreshSessions(currentUser.id);

    if (_scrollController.hasClients) {
      await Future.delayed(const Duration(milliseconds: 100));
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser!;
    final isMe = (User u) => u.id == currentUser.id;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: widget.friend.avatar != null
                      ? NetworkImage(widget.friend.avatar!)
                      : null,
                  child: widget.friend.avatar == null
                      ? Text(widget.friend.nickname.substring(0, 1))
                      : null,
                ),
                if (widget.friend.status == 'online')
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.friend.nickname,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (widget.friend.status == 'online')
                    const Text(
                      '在线',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    )
                  else
                    const Text(
                      '离线',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showChatOptions(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<MessageProvider>(
              builder: (context, messageProvider, child) {
                final messages =
                    messageProvider.getChatMessages(widget.friend.id);

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: widget.friend.avatar != null
                              ? NetworkImage(widget.friend.avatar!)
                              : null,
                          child: widget.friend.avatar == null
                              ? Text(widget.friend.nickname.substring(0, 1),
                                  style: const TextStyle(fontSize: 32))
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.friend.nickname,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '开始聊天吧',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5),
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final senderId = message.senderId;
                    final sender = isMe(widget.friend)
                        ? currentUser
                        : (senderId == currentUser.id
                            ? currentUser
                            : widget.friend);

                    return MessageBubble(
                      message: message,
                      isMe: isMe(sender!),
                      sender: sender,
                    );
                  },
                );
              },
            ),
          ),
          ChatInputField(
            onSend: _handleSend,
            onAttachmentTap: () => _showAttachmentOptions(context),
            isLoading: _messageProvider.isLoading,
          ),
        ],
      ),
    );
  }

  void _showChatOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('搜索聊天记录'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement search
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('清空聊天记录'),
              onTap: () {
                Navigator.pop(context);
                _showClearChatDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('拉黑'),
              onTap: () {
                Navigator.pop(context);
                _showBlockDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('图片'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement image picker
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement camera
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('文件'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement file picker
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('位置'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement location
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showClearChatDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: Text('确定要清空与 ${widget.friend.nickname} 的聊天记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement clear chat
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('拉黑'),
        content: Text('确定要拉黑 ${widget.friend.nickname} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement block
            },
            child: const Text('拉黑', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
