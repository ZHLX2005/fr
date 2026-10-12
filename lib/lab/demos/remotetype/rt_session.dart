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

/// RT1 P2C 快捷键指令明文（v0.5.4+ 两端协议）。
///
/// [keys] 末位是主键、其余是修饰键（['win','r'] = Win+R）。PC 端把它当
/// 「事件」处理（不进全文快照 diff）。独立成顶层纯函数以便单测，
/// 与 [rtSyncPlaintext] 同款理由。
Map<String, dynamic> rtHotkeyPlaintext(
  List<String> keys,
  int ts,
  String phoneId,
) {
  return {
    'hotkey': List<String>.of(keys),
    'ts': ts,
    'phoneId': phoneId,
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
    String? deviceToken,
  })  : _target = targetClientId,
        _token = token,
        _deviceToken = deviceToken,
        _phoneId = _randomHex(8),
        _sid = _randomHex(4) {
    _derivedFuture = rtDeriveFromKey(key);
    _serverBase = serverUrl.replaceAll(RegExp(r'/+$'), '');
  }

  /// 服务器设了 RT_TOKEN 时必须携带同一值，否则注册被 4403 拒绝（旧门禁）
  final String? _token;

  /// 统一登录换来的本服务凭据（新门禁）。服务端开启统一登录后，
  /// 注册帧必须带它，否则 4401 关闭。两条门禁可以并存，各带各的即可。
  final String? _deviceToken;

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
  // 非 final：reconnect 复用同一实例重建注册握手，每次尝试换新 Completer
  Completer<void> _registered = Completer<void>();
  bool _reconnecting = false;

  final _events = StreamController<RtEvent>.broadcast();
  Stream<RtEvent> get events => _events.stream;

  String get phoneId => _phoneId;
  bool get e2eConfirmed => _e2eConfirmed;

  /// WS 是否仍连着。socket 死亡时由 onDone 置空——页面重进 / 回前台
  /// 判断「要不要补重连」用，别拿它当强一致信号（半死 socket 要等帧才知）。
  bool get isConnected => _ws != null;

  /// 连接的目标 PC（页面重进时恢复 `_selectedClient` 用）
  String get targetClientId => _target;

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
    // 统一登录开启后这里不再是公开在线表：带身份也只回 200+ok:false（提示改用
    // /my/devices）。必须做成可识别的失败而不是返回空表——空表会让上层把
    // 「列表拿不到」误判成「确认没有 PC 在线」，那是一个假的结论。
    if (body['ok'] == false) {
      throw RtSessionException(
        RtJoinErrorKind.other,
        (body['hint'] ?? '该部署已收口 /clients（统一登录模式）').toString(),
      );
    }
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

    // 先探目标 PC 是否在线（给出比 WS 超时更明确的错误）。
    //
    // 只有「拿到真实在线表且目标不在其中」才拦；探测通道本身不可用绝不能拦：
    // 统一登录开启后 /clients 收口成 401（未带身份）或 200+ok:false（带了身份，
    // 提示改用 /my/devices）——两种都是**预期内**的响应，不是服务器不可达。
    // 这里曾经把 RtSessionException 一律 rethrow，结果是连接永远死在探测上、
    // 报「服务器响应 401」，WS 注册一步都没走到：列表能出（走 /my/devices）
    // 而连接必挂，就是那个 bug。
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
    } on RtSessionException catch (e) {
      if (e.kind == RtJoinErrorKind.pcOffline) rethrow;
      // 其余（401/403/接口收口/解析失败）→ 不阻断，让 WS 注册自己说话
    } catch (_) {
      // /clients 探测失败不阻断——有的部署可能关掉该接口，让 WS 自己说
    }

    await _openSocketAndRegister();
    _events.add(RtEvent(RtEventKind.connected));
  }

  /// 断线原地重连：保持 phoneId / seq / key 派生不变，PC 端按 clientId 路由
  /// 完全无感（全文快照语义 + seq 单调，PC 端 diff 自愈）。
  ///
  /// DemoSessionHost 的前台钩子自动调它（切 APP 回来自动重连），也可手动调。
  /// 安全性质：
  ///   - 已连接时 no-op（短暂后台回来 socket 还活着，不打断）
  ///   - 并发调用合并（[_reconnecting] 闸）
  ///   - 失败不上抛，只发 error 事件——自动路径没有可恢复动作，
  ///     下一个前台信号会再试；UI 从 events 流自行呈现
  Future<void> reconnect() async {
    if (_reconnecting || isConnected || _events.isClosed) return;
    _reconnecting = true;
    try {
      await _derivedFuture;
      await _openSocketAndRegister();
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.connected));
    } catch (_) {
      if (!_events.isClosed) {
        _events.add(RtEvent(RtEventKind.error, '自动重连失败，回到前台会再试'));
      }
    } finally {
      _reconnecting = false;
    }
  }

  /// 打开 WS 并完成注册握手——connect / reconnect 共用的传输层重建段。
  /// 幂等：先拆掉旧 socket（半死连接也要拆干净）再开新的。
  Future<void> _openSocketAndRegister() async {
    _registerTimeout?.cancel();
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    final registered = Completer<void>();
    _registered = registered;

    final wsUrl = '${_serverBase.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = channel;
    _wsSub = channel.stream.listen(_onFrame, onDone: () {
      // 死亡即置空：isConnected 的真相来源，重进/回前台的补连判断靠它
      _ws = null;
      _wsSub = null;
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.disconnected, '连接关闭'));
    }, onError: (Object e) {
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.error, '连接错误：$e'));
    });

    _sendJson({
      'type': 'register',
      'role': 'phone',
      'phoneId': _phoneId,
      if (_token != null && _token.isNotEmpty) 'token': _token,
      if (_deviceToken != null && _deviceToken.isNotEmpty)
        'deviceToken': _deviceToken,
    });
    _registerTimeout = Timer(const Duration(seconds: 8), () {
      if (registered.isCompleted) return;
      registered.completeError(
        RtSessionException(RtJoinErrorKind.serverUnreachable, '服务器无响应（注册超时）'),
      );
    });
    await registered.future;
  }

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
        // 注册阶段的 error 帧要转成可理解的异常：不同原因对应完全不同的动作
        if (!_registered.isCompleted) {
          final reason = msg['error']?.toString() ?? '';
          if (reason == 'auth_required' || reason.contains('auth_required')) {
            _registered.completeError(
              RtSessionException(
                RtJoinErrorKind.authFailed,
                '服务器要求统一登录：先在统一登录平台登录，再回到本页',
              ),
            );
          } else if (reason.contains('token')) {
            _registered.completeError(
              RtSessionException(
                RtJoinErrorKind.authFailed,
                msg['hint']?.toString() != null
                    ? '服务器拒绝了本机凭据：${msg['hint']}'
                    : '服务器开启了访问 token（RT_TOKEN），请在连接页填写同一 token',
              ),
            );
          } else {
            _registered.completeError(
              RtSessionException(RtJoinErrorKind.other, '服务器拒绝：$reason'),
            );
          }
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
  /// 返回 true = 信封已实际发出（WS 未连接时返回 false，调用方可据此
  /// 决定是否做「发送后清空」一类不可逆动作）。
  ///
  /// [enterMode]：'\n' 在 PC 侧的注入方式（'enter'=普通 Enter / 'shift_enter'
  /// = Shift+Enter，微信等「Enter=发送」的框里只换行不发送）。null/空 = 不带
  /// 字段，PC 端走本地配置兜底（老版本 PC 忽略未知字段，双向兼容）。
  Future<bool> syncText(String text, {String? enterMode}) async {
    final derived = await _derivedFuture;
    if (_ws == null) return false;
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
    return true;
  }

  /// 发送一条快捷键指令（v0.5.4+ 两端协议）。
  ///
  /// [keys] 末位是主键、其余是修饰键（['win','r'] = Win+R），合法名字见
  /// `rt_constants.dart` 的 kShortcutPresets 注释。与 [syncText] 共用 seq 域
  /// 与加密路径；PC 端把它当「事件」处理（不进全文快照 diff，无 mirror
  /// 推进），重复发送会重复触发——调用方不需要也不应该做去重。
  ///
  /// 返回 true = 信封已实际发出（WS 未连接返回 false）。
  Future<bool> syncHotkey(List<String> keys) async {
    if (keys.isEmpty) return false;
    final derived = await _derivedFuture;
    if (_ws == null) return false;
    _seq += 1;
    final envelope = await rtSeal(
      key: derived.keyPhoneToPc,
      aad: rtBuildAad(derived.room, kRtDirPhoneToPc, _seq),
      plaintext: rtHotkeyPlaintext(
        keys,
        DateTime.now().millisecondsSinceEpoch,
        _phoneId,
      ),
      sid: _sid,
      seq: _seq,
    );
    _sendJson({'clientId': _target, 'text': jsonEncode(envelope)});
    return true;
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
