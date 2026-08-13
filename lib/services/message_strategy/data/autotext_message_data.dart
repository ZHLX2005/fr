import '../interfaces/message_data.dart';

/// Auto-text message data: plain text auto-rendered as markdown
class AutoTextMessageData implements IMessageData {
  final String content;

  AutoTextMessageData(this.content);

  @override
  String get type => 'autotext';
}
