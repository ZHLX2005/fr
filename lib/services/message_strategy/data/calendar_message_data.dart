import '../interfaces/message_data.dart';

/// 日期范围消息数据
class CalendarMessageData implements IMessageData {
  final DateTime? startDate;
  final DateTime? endDate;

  CalendarMessageData({this.startDate, this.endDate});

  @override
  String get type => 'calendar';
}
