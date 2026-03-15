import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

class MessageBubble extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final difference = now.difference(message.createdAt);

    String timeText;
    if (difference.inMinutes < 1) {
      timeText = '刚刚';
    } else if (difference.inHours < 1) {
      timeText = '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      timeText = DateFormat('HH:mm').format(message.createdAt);
    } else {
      timeText = DateFormat('MM/dd HH:mm').format(message.createdAt);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && sender != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 12),
                child: Text(
                  sender!.nickname,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe && sender?.avatar != null)
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(sender!.avatar!),
                  ),
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      gradient: isMe
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
                        Text(
                          message.content,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isMe
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isMe
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
    if (!isMe) return const SizedBox.shrink();

    switch (message.status) {
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
}
