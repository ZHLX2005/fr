part of 'lan_event.dart';

/// 通道消息事件
class ChannelMessageEvent extends LanEvent {
  const ChannelMessageEvent({
    required this.sourceDeviceId,
    required this.channel,
    required this.payload,
    required this.timestamp,
  });
  final String sourceDeviceId;
  final String channel;
  final Map<String, dynamic> payload;
  @override
  final DateTime timestamp;
}
