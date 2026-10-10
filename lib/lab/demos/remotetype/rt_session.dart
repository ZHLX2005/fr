// lib/lab/demos/remotetype/rt_session.dart
//
// RemoteType 直连会话：连 mn-rt server.js（唯一后端）——加密全文信封 → PC 注入 → ACK 回流。
// 纯数据控制层（无 UI），UI 见 rt_page.dart。
//
// 协议（RT1 直连版，与 mn-rt client/lib/rt-align.js 构成两端）：
//   - WS 注册：{type:'register', role:'phone', phoneId}
//   - 同步：{clientId: <目标PC>, text: <信封JSON>}，服务端按 clientId 路由
//   - ACK：PC 经服务端按 phoneId 反向路由 {type:'ack', ack:<信封>}，
//     能解开 = 端到端闭环成立（GCM tag 即持钥证明，无需独立配对握手）
//   - 房间号不再是路由地址，仅作为 AAD 上下文标签从 key 派生（两端一致，向量不变）

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'rt_constants.dart';
import 'rt_crypto.dart';

/// 连接失败的可区分错误（文案直接对应用户动作）
enum RtJoinErrorKind { serverUnreachable, pcOffline, authFailed, other }

/// RT1 P2C 快照明文（与 mn-rt client/lib/rt-align.js 的解析端对齐）。
///
/// [enterMode] 非空时携带（'enter' | 'shift_enter'），空串视为未选择；
/// 老版本 PC 解析 JSON 时忽略未知字段，双向兼容。独立成顶层纯函数
/// 以便单测（向量对拍不感知该字段，加密层无改动）。
Map<String, dynamic> rtSyncPlaintext(
  String text,
  int ts,
  String phoneId, {
  String? enterMode,
}) {
  final hasMode = enterMode != null && enterMode.isNotEmpty;
  return {
    'text': text,
    'ts': ts,
    'phoneId': phoneId,
    if (hasMode) 'enterMode': enterMode,
  };
}

class RtSessionException implements Exception {
  RtSessionException(this.kind, this.message);

  final RtJoinErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 会话阶段事件（UI 只消费这一个流）
enum RtEventKind { connected, e2eConfirmed, disconnected, deliveryFailed, error }

class RtEvent {
  RtEvent(this.kind, [this.detail]);

  final RtEventKind kind;
  final String? detail;
}

class RtSession {
  RtSession({
    required String serverUrl,
    required String key,
    required String targetClientId,
    String? token,
  })  : _target = targetClientId,
        _token = token,
        _phoneId = _randomHex(8),
        _sid = _randomHex(4) {
    _derivedFuture = rtDeriveFromKey(key);
    _serverBase = serverUrl.replaceAll(RegExp(r'/+$'), '');
  }

  /// 服务器设了 RT_TOKEN 时必须携带同一值，否则注册被 4403 拒绝
  final String? _token;

  late final String _serverBase;
  late final Future<RtDerived> _derivedFuture;
  RtDerived? _derived;
  final String _target;

  final String _phoneId;
  final String _sid;
  int _seq = 0;
  int _lastAckSeen = 0;
  bool _e2eConfirmed = false;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _registerTimeout;

  final _events = StreamController<RtEvent>.broadcast();
  Stream<RtEvent> get events => _events.stream;

  String get phoneId => _phoneId;
  bool get e2eConfirmed => _e2eConfirmed;

  /// 拉取在线 PC 列表（GET /clients），供连接前选择目标
  static Future<List<String>> listClients(String serverUrl) async {
    final base = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final resp = await http
        .get(Uri.parse('$base/clients'))
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      throw RtSessionException(RtJoinErrorKind.serverUnreachable, '服务器响应 ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final clients = body['clients'];
    if (clients is! List) return const [];
    return [
      for (final c in clients)
        if (c is Map && c['clientId'] is String) c['clientId'] as String,
    ];
  }

  /// 连接 server 并注册手机角色
  Future<void> connect() async {
    final derived = await _derivedFuture;
    _derived = derived;

    // 先探目标 PC 是否在线（给出比 WS 超时更明确的错误）
    try {
      final online = await listClients(_serverBase);
      if (!online.contains(_target)) {
        throw RtSessionException(
          RtJoinErrorKind.pcOffline,
          online.isEmpty
              ? '目标 PC $_target 不在线（服务器当前无 PC 上线）'
              : '目标 PC $_target 不在线；在线：${online.join(', ')}',
        );
      }
    } on RtSessionException {
      rethrow;
    } catch (_) {
      // /clients 探测失败不阻断——有的部署可能关掉该接口，让 WS 自己说
    }

    final wsUrl = '${_serverBase.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = channel;
    _wsSub = channel.stream.listen(_onFrame, onDone: () {
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.disconnected, '连接关闭'));
    }, onError: (Object e) {
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.error, '连接错误：$e'));
    });

    _sendJson({
      'type': 'register',
      'role': 'phone',
      'phoneId': _phoneId,
      if (_token != null && _token.isNotEmpty) 'token': _token,
    });
    _registerTimeout = Timer(const Duration(seconds: 8), () {
      if (_registered.isCompleted) return;
      _registered.completeError(
        RtSessionException(RtJoinErrorKind.serverUnreachable, '服务器无响应（注册超时）'),
      );
    });
    await _registered.future;
    _events.add(RtEvent(RtEventKind.connected));
  }

  final Completer<void> _registered = Completer<void>();

  void _onFrame(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'registered':
        if (!_registered.isCompleted) _registered.complete();
        break;
      case 'error':
        // 注册阶段的 error 帧要转成可理解的异常（如服务器设了 RT_TOKEN 而本端未携带）
        if (!_registered.isCompleted) {
          final reason = msg['error']?.toString() ?? '';
          _registered.completeError(
            RtSessionException(
              reason.contains('token')
                  ? RtJoinErrorKind.authFailed
                  : RtJoinErrorKind.other,
              reason.contains('token')
                  ? '服务器开启了访问 token（RT_TOKEN），请在连接页填写同一 token'
                  : '服务器拒绝：$reason',
            ),
          );
        } else if (!_events.isClosed) {
          _events.add(RtEvent(RtEventKind.error, '服务器：${msg['error']}'));
        }
        break;
      case 'ack_status':
        if (msg['ok'] != true) {
          _events.add(RtEvent(RtEventKind.deliveryFailed, '投递失败：${msg['status']}'));
        }
        break;
      case 'ack':
        _openAck(msg['ack']);
        break;
      default:
        break; // welcome / pong 等
    }
  }

  /// PC 的累积确认：解开即证明对端持钥（端到端闭环）
  Future<void> _openAck(dynamic ackDynamic) async {
    final derived = _derived;
    if (derived == null || ackDynamic is! Map) return;
    final ack = ackDynamic.cast<String, dynamic>();
    final ackSeq = (ack['seq'] as num?)?.toInt() ?? 0;
    if (ackSeq <= _lastAckSeen) return;
    _lastAckSeen = ackSeq;
    try {
      await rtOpen(
        key: derived.keyPcToPhone,
        aad: rtBuildAad(derived.room, kRtDirPcToPhone, ackSeq),
        envelope: ack,
      );
      _e2eConfirmed = true;
      _events.add(RtEvent(RtEventKind.e2eConfirmed));
    } catch (_) {
      // key 不一致：保持未确认状态，由 UI 展示
    }
  }

  /// 同步全文到 PC（全文快照语义，调用方负责防抖）。
  ///
  /// [enterMode]：'\n' 在 PC 侧的注入方式（'enter'=普通 Enter / 'shift_enter'
  /// = Shift+Enter，微信等「Enter=发送」的框里只换行不发送）。null/空 = 不带
  /// 字段，PC 端走本地配置兜底（老版本 PC 忽略未知字段，双向兼容）。
  Future<void> syncText(String text, {String? enterMode}) async {
    final derived = await _derivedFuture;
    if (_ws == null) return;
    _seq += 1;
    final envelope = await rtSeal(
      key: derived.keyPhoneToPc,
      aad: rtBuildAad(derived.room, kRtDirPhoneToPc, _seq),
      plaintext: rtSyncPlaintext(
        text,
        DateTime.now().millisecondsSinceEpoch,
        _phoneId,
        enterMode: enterMode,
      ),
      sid: _sid,
      seq: _seq,
    );
    _sendJson({'clientId': _target, 'text': jsonEncode(envelope)});
  }

  void _sendJson(Map<String, dynamic> obj) {
    try {
      _ws?.sink.add(jsonEncode(obj));
    } catch (e) {
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.error, '发送失败：$e'));
    }
  }

  Future<void> dispose() async {
    _registerTimeout?.cancel();
    await _wsSub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    await _events.close();
  }
}

final Random _rng = Random.secure();

String _randomHex(int bytes) =>
    List<int>.generate(bytes, (_) => _rng.nextInt(256))
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
