import '../interfaces/message_data.dart';

/// Markdown format message data
class MarkdownMessageData implements IMessageData {
  final String content;

  MarkdownMessageData(this.content);

  @override
  String get type => 'markdown';
}
