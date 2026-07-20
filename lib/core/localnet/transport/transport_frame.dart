import 'dart:convert';
import 'dart:typed_data';

/// 传输层帧 — 所有传输后端统一的数据结构
///
/// 序列化用 base64 编码 payload（兼容 JSON）；时间戳用 ISO8601。
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

  Map<String, dynamic> toJson() => {
        'channelName': channelName,
        'sourceDeviceId': sourceDeviceId,
        'payload': base64Encode(payload),
        'timestamp': timestamp.toIso8601String(),
      };

  factory TransportFrame.fromJson(Map<String, dynamic> json) {
    return TransportFrame(
      channelName: json['channelName'] as String? ?? '',
      sourceDeviceId: json['sourceDeviceId'] as String? ?? 'unknown',
      payload: base64Decode(json['payload'] as String? ?? ''),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
