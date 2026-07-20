import 'dart:convert';
import 'dart:typed_data';

/// Chat 消息载荷 — LAN/Relay 通用的 chat 协议格式
///
/// LAN 模式：作为 Map 传给 sendTo(channel, {'text': ..., 'alias': ...})
/// Relay 模式：序列化为 TransportFrame.payload (UTF-8 JSON)
class ChatPayload {
  const ChatPayload({required this.text, this.alias});

  /// 消息文本
  final String text;

  /// 发送者别名（可选，对端可用此字段显示昵称）
  final String? alias;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        if (alias != null) 'alias': alias,
      };

  factory ChatPayload.fromJson(Map<String, dynamic> json) => ChatPayload(
        text: json['text'] as String? ?? '',
        alias: json['alias'] as String?,
      );

  /// 编码为 UTF-8 JSON bytes（Relay 模式用）
  Uint8List toBytes() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// 从 UTF-8 JSON bytes 解码
  factory ChatPayload.fromBytes(Uint8List bytes) {
    try {
      return ChatPayload.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      return ChatPayload(text: utf8.decode(bytes, allowMalformed: true));
    }
  }
}
