import 'dart:async';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'models/localnet_message.dart';

/// LocalNet biz 服务 — 订阅 Transport 事件总线，驱动 UI
///
/// **零发现、零连接逻辑** — biz 层只通过订阅 [Transport.events]
/// 的 'chat-message' 事件收发消息，无需 scope 协调。
class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  fw.Transport? _transport;

  /// 当前活跃传输（外部可订阅事件总线）
  fw.Transport? get transport => _transport;

  /// 本节点 id
  String? get myNodeId => _transport?.myNodeId;

  /// 绑定一个已建立连接的 transport（由 localnet widget 触发）
  void attach(fw.Transport transport) {
    detach();
    _transport = transport;
    _evtSub = transport.events.listen(_onTransportEvent);
    debugLog.i('Localnet', 'attached to transport: ${transport.myNodeId}');
  }

  /// 解绑（切换模式时）
  void detach() {
    _evtSub?.cancel();
    _evtSub = null;
    _transport = null;
    _messages.clear();
    _messagesController.add(_snapshot());
  }

  // ============ 消息存储（事件驱动） ============

  final Map<String, LocalnetMessage> _messages = {};
  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();

  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;

  List<LocalnetMessage> get messages => _snapshot();

  List<LocalnetMessage> _snapshot() =>
      List.unmodifiable(_messages.values.toList());

  void _onTransportEvent(fw.TransportEvent ev) {
    if (ev.topic == 'chat-message') {
      final msg = LocalnetMessage.fromJson(
          ev.data.map<String, dynamic>((k, v) => MapEntry(k, v)));
      _messages[msg.id] = msg;
      _messagesController.add(_snapshot());
    }
  }

  /// 本地发送消息：通过 transport 事件总线广播
  void sendMessage(LocalnetMessage msg) {
    final t = _transport;
    if (t == null) return;
    // 本地立即显示
    _messages[msg.id] = msg;
    _messagesController.add(_snapshot());
    // 广播给对端
    t.broadcastEvent('chat-message', msg.toJson());
  }

  // ============ 生命周期 ============

  StreamSubscription<fw.TransportEvent>? _evtSub;
}

final localnetService = LocalnetService();

class debugLog {
  static void i(String tag, String msg) {
    // ignore: avoid_print
    print('[$tag] $msg');
  }
}