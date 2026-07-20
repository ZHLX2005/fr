import 'dart:typed_data';

class TransportFrame {
  const TransportFrame({
    required this.channelName,
    required this.sourceDeviceId,
    required this.payload,
    required this.timestamp,
  });

  final String channelName;
  final String sourceDeviceId;
  final Uint8List payload;
  final DateTime timestamp;
}
