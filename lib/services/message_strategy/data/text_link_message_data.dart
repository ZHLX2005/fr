import '../interfaces/message_data.dart';

/// 支持 schema 内嵌链接的纯文本消息
/// 语法: [显示文字](fr://lab/demo/xxx) / [文字](fr://lab/core/xxx)
class TextLinkMessageData implements IMessageData {
  final String content;

  TextLinkMessageData(this.content);

  @override
  String get type => 'text_link';
}