import '../interfaces/message_data.dart';

/// Card Manager 消息数据。
///
/// 这张卡片本身是一个「卡片调度器」：卡片上的按钮通过全局
/// [MessagePanelController] 往面板追加其它类型的卡片。
class CardManagerMessageData implements IMessageData {
  /// 卡片标题
  final String title;

  const CardManagerMessageData({this.title = '卡片管理器'});

  @override
  String get type => 'card_manager';
}
