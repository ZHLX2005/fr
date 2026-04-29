import '../interfaces/message_data.dart';

/// HTML format message data
class HtmlMessageData implements IMessageData {
  final String content;

  HtmlMessageData(this.content);

  @override
  String get type => 'html';
}
