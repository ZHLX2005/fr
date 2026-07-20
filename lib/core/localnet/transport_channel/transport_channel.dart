import 'dart:typed_data';

import '../transport/transport_frame.dart';

/// 传输通道抽象 — 在 LAN 后端是 HTTP P2P，在 Relay 后端是 WS 多路复用。
///
/// ChannelManager.sendTo/watchChannel 内部委托给 TransportChannel。
/// 业务层不感知底层差异。
abstract interface class TransportChannel {
  /// 打开逻辑通道（LAN：注册 HTTP `/channel/<name>` handler；Relay：发 OPEN frame）。
  Future<void> open({
    required String channelName,
    required String remoteDeviceId,
  });

  /// 发送消息到对端。
  Future<SendResult> send(String channelName, Uint8List data);

  /// 订阅某 channel 的入站消息。
  Stream<TransportFrame> watch(String channelName);

  /// 关闭通道（LAN：注销 handler；Relay：发 CLOSE frame）。
  Future<void> close();
}

/// TransportChannel.send 返回值。
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
