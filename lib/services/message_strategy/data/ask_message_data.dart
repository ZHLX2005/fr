import '../interfaces/message_data.dart';

/// Ask message data - question with input field
class AskMessageData implements IMessageData {
  /// Question text
  final String question;

  /// Placeholder text for input
  final String placeholder;

  AskMessageData({
    required this.question,
    this.placeholder = '请输入...',
  });

  @override
  String get type => 'ask';
}
