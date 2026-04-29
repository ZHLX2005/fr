import '../interfaces/message_data.dart';

/// Plain text message data
class TextMessageData implements IMessageData {
  final String text;

  TextMessageData(this.text);

  @override
  String get type => 'text';
}
