/// 通道消息
class ChannelMessage {
  const ChannelMessage({
    required this.sourceDeviceId,
    required this.channel,
    required this.payload,
    required this.timestamp,
  });

  final String sourceDeviceId;
  final String channel;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
}
