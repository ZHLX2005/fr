import 'package:flutter/material.dart';
import '../../../core/schema/schema.dart';
import '../interfaces/interfaces.dart';
import '../data/text_link_message_data.dart';

/// Strategy for rendering text messages with internal navigation links.
/// 复用 SchemaText:[文字](fr://lab/demo/xxx) / [文字](fr://lab/core/xxx)
class TextLinkMessageWidgetStrategy
    extends MessageWidgetStrategy<TextLinkMessageData> {
  @override
  Widget build(BuildContext context, TextLinkMessageData data) {
    return SchemaText(data.content);
  }

  @override
  TextLinkMessageData createMockData() => TextLinkMessageData(_mock);
}

/// 写死的多案例 mock:覆盖 core 页面跳转、demo 跳转、多链接共存、纯文本混排
const String _mock = '''欢迎使用 Link Text！这是一条支持内部跳转的纯文本消息。

试试点击这些链接:
- 打开 [个人中心](fr://lab/core/profile)
- 跳转 [课表](fr://lab/core/timetable)
- 回到 [AI 助手](fr://lab/core/home)
- 试用 [时钟](fr://lab/demo/时钟)
- 查看 [悬浮截屏](fr://lab/demo/悬浮截屏)

注意:仅支持 fr:// 协议,其他链接将作为纯文本显示。''';