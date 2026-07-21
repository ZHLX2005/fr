import 'dart:async';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'models/localnet_message.dart';

/// LocalNet biz 服务 — 订阅 Transport 事件总线，驱动 UI
///
/// **零发现、零连接逻辑** — biz 层只通过订阅 [Transport.events]
/// 和 [Transport.watchScope] 接收数据，自己解释。
class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  fw.Transport? _transport;
  String? _activeScope;

  /// 当前活跃传输（外部可订阅事件总线）
  fw.Transport? get transport => _transport;

  /// 当前活跃 scope
  String? get activeScope => _activeScope;

  /// 本节点 id
  String? get myNodeId => _transport?.myNodeId;

  /// 绑定一个已建立连接的 transport + scope（由 localnet widget 触发）
  void attach(fw.Transport transport, String scope) {
    detach();
    _transport = transport;
    _activeScope = scope;
    _chatSub = transport.watchScope(scope).listen(_onScopeUpdate);
    _evtSub = transport.events.listen(_onTransportEvent);
    debugLog.i('Localnet', 'attached to scope: $scope');
  }

  /// 解绑（切换模式时）
  void detach() {
    _chatSub?.cancel();
    _evtSub?.cancel();
    _chatSub = null;
    _evtSub = null;
    _transport = null;
    _activeScope = null;
    _messages.clear();
    _messagesController.add(_snapshot());
  }

  // ============ 消息存储（数据驱动） ============

  final Map<String, LocalnetMessage> _messages = {};
  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();

  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;

  List<LocalnetMessage> get messages => _snapshot();

  List<LocalnetMessage> _snapshot() =>
      List.unmodifiable(_messages.values.toList());

  void _onScopeUpdate(fw.DataLog log) {
    // log.state 是 scope 内最终一致状态 — 业务自己解释
    // 这里假设 state['messages'] 是 List<Map>
    final raw = log.state['messages'];
    if (raw is! List) return;
    _messages.clear();
    for (final entry in raw) {
      if (entry is Map) {
        final msg = LocalnetMessage.fromJson(entry.cast<String, dynamic>());
        _messages[msg.id] = msg;
      }
    }
    _messagesController.add(_snapshot());
  }

  void _onTransportEvent(fw.TransportEvent ev) {
    // 新 peer 加入 scope → 重推当前状态
    if (ev.topic == 'peer-joined-scope') {
      final scope = ev.data['scope'] as String?;
      if (scope == _activeScope) {
        final t = _transport;
        if (t != null) t.broadcastScope(scope!);
      }
    }
  }

  /// 本地发送消息：写到 scope 状态 → 全广播（raft 风格）
  void sendMessage(LocalnetMessage msg) {
    final t = _transport;
    final scope = _activeScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    if (log == null) return;
    final list = (log.state['messages'] as List?)?.cast<Map>() ?? <Map>[];
    list.add(msg.toJson());
    log.merge({'messages': list}, localNodeId: t.myNodeId);
    // 本地：sender 立即看到自己的消息（广播会过滤自己的包）
    _onScopeUpdate(log);
    // 广播 scope 全量状态给其他节点
    t.broadcastScope(scope);
  }

  // ============ 生命周期 ============

  StreamSubscription<fw.DataLog>? _chatSub;
  StreamSubscription<fw.TransportEvent>? _evtSub;
}

final localnetService = LocalnetService();

class debugLog {
  static void i(String tag, String msg) {
    // ignore: avoid_print
    print('[$tag] $msg');
  }
}