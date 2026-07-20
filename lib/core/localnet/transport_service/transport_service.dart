import 'dart:async';
import 'dart:typed_data';

/// 传输服务抽象 — LAN/Relay 统一的通信接口
///
/// LAN 实现：ChannelManager（HTTP P2P）
/// Relay 实现：RelayChannel（WS 帧）
///
/// 职责：
/// 1. 点对点消息收发 (sendTo / watchChannel)
/// 2. 连接状态事件 (connected / disconnected / reconnecting / error)
/// 3. 活性检测（心跳/ping）
/// 4. 创建 Session 自动同步状态
abstract class TransportService {
  /// 发送消息到指定对端
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  );

  /// 发送原始消息到指定对端
  Future<SendResult> sendRaw(
      String targetDeviceId, String channel, Uint8List data);

  /// 订阅通道消息
  Stream<TransportMessage> watchChannel(String channel);

  /// 传输层事件流（连接状态、错误等）
  Stream<TransportEvent> get events;

  /// 当前连接状态
  TransportConnectionState get connectionState;

  /// 本端 deviceId
  String get myDeviceId;
}

/// 传输消息
class TransportMessage {
  const TransportMessage({
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

/// 传输层事件
sealed class TransportEvent {
  const TransportEvent();
}

class Connected extends TransportEvent {
  const Connected();
}

class Disconnected extends TransportEvent {
  const Disconnected({this.error});
  final Object? error;
}

class Reconnecting extends TransportEvent {
  const Reconnecting();
}

class TransportError extends TransportEvent {
  const TransportError(this.error);
  final Object error;
}

/// 传输连接状态
enum TransportConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// 发送结果
class SendResult {
  const SendResult({required this.success, this.error, this.statusCode});

  final bool success;
  final String? error;
  final int? statusCode;

  factory SendResult.ok({int? statusCode}) =>
      SendResult(success: true, statusCode: statusCode);

  factory SendResult.fail(String error) =>
      SendResult(success: false, error: error);
}
