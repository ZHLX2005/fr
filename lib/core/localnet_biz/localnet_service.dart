import 'dart:async';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/device_id_service.dart';

/// LocalNet biz 服务 — 订阅 Transport 事件总线，驱动 UI
///
/// **零发现、零连接逻辑** — biz 层只通过订阅 [Transport.events]
/// 和 [Transport.watchScope] 接收数据，自己解释。
class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final ConfigService config = configService;

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
    // 业务层可订阅其他事件（peer-joined-scope 等）
  }

  /// 本地发送消息：写到 scope 状态（其他节点自动收到）
  void sendMessage(LocalnetMessage msg) {
    final t = _transport;
    final scope = _activeScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    if (log == null) return;
    final list = (log.state['messages'] as List?)?.cast<Map>() ?? <Map>[];
    list.add(msg.toJson());
    log.merge({'messages': list}, localNodeId: t.myNodeId);
  }

  // ============ 生命周期 ============

  Future<void> init() async {
    await config.init();
  }

  /// 更新配置（重新启动）
  Future<void> updateConfig(LocalnetConfig newConfig) async {
    await config.updateConfig(newConfig);
    if (_transport != null) {
      // 重启连接
      await _transport!.stop();
      detach();
    }
  }

  /// 兼容旧 API：serviceState
  String get serviceState => isReady ? 'RUNNING' : 'STOPPED';

  /// 兼容旧 API：isReady（基于是否有活跃 transport）
  bool get isReady => _transport != null;

  /// 兼容旧 API：devices（返回空，因为 biz 层不直接管理节点）
  List<LocalnetDevice> get devices => const [];

  Future<void> stop() async {
    detach();
  }

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