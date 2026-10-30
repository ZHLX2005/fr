// lib/core/remotetype/protocol/rt_session.dart
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

import '../data/rt_constants.dart';
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
  return {'hotkey': List<String>.of(keys), 'ts': ts, 'phoneId': phoneId};
}

/// RT1 P2C 鼠标事件明文（v0.6.0+ 触摸板协议）。
///
/// [mouse] 三种形状之一（合法性由 PC 端 rt-align normalizeMouseOp 白名单
/// 把关，这里只做密封）：
///   {'a':'move',   'dx':int, 'dy':int}                相对移动（像素）
///   {'a':'button', 'button':str, 'kind':str}          left/right/middle × click/press/release
///   {'a':'scroll', 'dx':int, 'dy':int}                滚轮格数（正 = 下/右）
/// PC 端把它当「事件」处理且**不回 ACK**（高频通道，流量减半）。
/// 独立成顶层纯函数以便单测，与 [rtSyncPlaintext] 同款理由。
Map<String, dynamic> rtMousePlaintext(
  Map<String, dynamic> mouse,
  int ts,
  String phoneId,
) {
  return {
    'mouse': Map<String, dynamic>.of(mouse),
    'ts': ts,
    'phoneId': phoneId,
  };
}

/// RT1 P2C 虚拟手柄指令明文（v0.7.0+ vpad_* 协议）。
///
/// [cmd] 一条 vpad 指令（action + 字段，形状由 PC 端 normalizeVpadOp
/// 白名单把关，与 rust input-agent vpad.rs parse_* 一致）：
///   {'action':'vpad_init',  'vpad_slot':1}
///   {'action':'vpad_release','vpad_handle':'pad1'} / {'action':'vpad_release_all'}
///   {'action':'vpad_button', 'vpad_handle':'pad1','vpad_button':'a','vpad_value_bool':true}
///   {'action':'vpad_trigger','vpad_handle':'pad1','vpad_trigger':'lt','vpad_value':1.0}
///   {'action':'vpad_dpad',   'vpad_handle':'pad1','vpad_dir':'up'}
/// 与 hotkey/mouse 同属「事件」语义：seq 去重之前处理、不回 ACK；rust 端按
/// handle 维护累积状态，press/release 成对发送即可。独立成顶层纯函数以便单测。
Map<String, dynamic> rtVpadPlaintext(
  Map<String, dynamic> cmd,
  int ts,
  String phoneId,
) {
  return {'vpad': Map<String, dynamic>.of(cmd), 'ts': ts, 'phoneId': phoneId};
}

/// RT1 P2C 图片传输明文（v0.8.0+ 文件模块·实时拍照协议）。
///
/// [img] 一条 img 指令（op + 字段，形状由 PC 端 rt-image.js 的
/// normalizeImageOp 白名单把关，两端分片大小以 kRtImageChunkSize 为准）：
///   {'op':'begin', 'id':str8hex, 'n':int, 'size':int, 'mime':'image/jpeg'}
///   {'op':'chunk', 'id':str, 'i':int, 'd':base64}
///   {'op':'end',   'id':str}   —— PC 端到齐并写入剪贴板后才回最后一块的 ACK
///   {'op':'abort', 'id':str}
/// 与 hotkey/mouse 同属「事件」语义（seq 去重之前处理、不碰全文快照状态机），
/// 但**逐条回 ACK**：begin/chunk 的 ACK = 分片已落袋（驱动进度条与续传补缺），
/// end 的 ACK = 整图已进剪贴板。独立成顶层纯函数以便单测。
Map<String, dynamic> rtImagePlaintext(
  Map<String, dynamic> img,
  int ts,
  String phoneId,
) {
  return {'img': Map<String, dynamic>.of(img), 'ts': ts, 'phoneId': phoneId};
}

class RtSessionException implements Exception {
  RtSessionException(this.kind, this.message);

  final RtJoinErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 会话阶段事件（UI 只消费这一个流）
enum RtEventKind {
  connected,
  e2eConfirmed,
  disconnected,
  deliveryFailed,
  error,
}

class RtEvent {
  RtEvent(this.kind, [this.detail, this.willRetry = false]);

  final RtEventKind kind;
  final String? detail;

  /// disconnected 专用：true = socket 死了但会话正在自动重连，UI 只应把
  /// 连接态置灰、**不要**弹「连接断开」；重连那一次失败后会再发一条
  /// willRetry=false 的事件，那时才是最终断开。
  final bool willRetry;
}

class RtSession {
  RtSession({
    required String serverUrl,
    required String key,
    required String targetClientId,
    String? token,
    String? deviceToken,
  }) : _target = targetClientId,
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
  // 应用层心跳：周期发 {type:'ping'}，服务端回 {type:'pong'}（server.js 路由）。
  // 没有它，半开连接（切网/NAT 超时，对端 FIN 到不了）会永远 isConnected==true，
  // 自动重连永远不触发而发送静默进黑洞——「自动重连不稳定、手动重连一点就好」
  // 的根因。任何入站帧都算活着（pong / ack / welcome 同等有效）。
  Timer? _pingTimer;
  DateTime _lastPongAt = DateTime.now();
  static const Duration _kPingInterval = Duration(seconds: 15);
  static const Duration _kPingDeadLine = Duration(seconds: 45);
  // 断线自动重连梯：延迟递进重试有限轮；期间发 willRetry=true 的 disconnected
  // （UI 置灰不弹提示），全部失败才发最终 disconnected。
  Timer? _autoReconnectTimer;
  static const List<Duration> _kRetryDelays = [
    Duration(milliseconds: 1500),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];
  int _retryRound = 0; // 已消耗的重试轮次；成功归零
  // 非 final：reconnect 复用同一实例重建注册握手，每次尝试换新 Completer
  Completer<void> _registered = Completer<void>();
  bool _reconnecting = false;

  final _events = StreamController<RtEvent>.broadcast();
  Stream<RtEvent> get events => _events.stream;

  /// PC 累积确认流：每解开一个 ACK 信封，吐出它确认的 p2c seq（applied_seq）。
  /// 全文快照只需最新一条（e2eConfirmed 事件已覆盖），图片分片进度条靠
  /// 逐条监听。broadcast：无人监听时事件丢弃，不影响会话。
  final _ackApplied = StreamController<int>.broadcast();
  Stream<int> get ackAppliedSeqs => _ackApplied.stream;

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
      throw RtSessionException(
        RtJoinErrorKind.serverUnreachable,
        '服务器响应 ${resp.statusCode}',
      );
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
  /// 立即试一轮；失败会沿 [_kRetryDelays] 的重试梯继续（见 [_attemptReconnect]），
  /// 全部轮次耗尽才发最终 disconnected。安全性质：
  ///   - 已连接时 no-op（短暂后台回来 socket 还活着，不打断）
  ///   - 并发调用合并（[_reconnecting] 闸）
  Future<void> reconnect() => _attemptReconnect();

  /// 重试梯的一轮：失败排下一轮（延迟递进），耗尽才报最终断开。
  Future<void> _attemptReconnect() async {
    if (_reconnecting || isConnected || _events.isClosed) return;
    _reconnecting = true;
    try {
      await _derivedFuture;
      await _openSocketAndRegister();
      _retryRound = 0;
      if (!_events.isClosed) _events.add(RtEvent(RtEventKind.connected));
    } catch (_) {
      if (!_events.isClosed) _scheduleNextRetry();
    } finally {
      _reconnecting = false;
    }
  }

  /// 排下一轮重试；轮次耗尽则发**最终** disconnected（willRetry=false）。
  void _scheduleNextRetry() {
    _autoReconnectTimer?.cancel();
    if (_retryRound >= _kRetryDelays.length) {
      _events.add(
        RtEvent(
          RtEventKind.disconnected,
          '自动重连 ${_kRetryDelays.length} 次均失败；点「重连」或回到前台会再试',
        ),
      );
      return;
    }
    final delay = _kRetryDelays[_retryRound++];
    _autoReconnectTimer = Timer(delay, () {
      unawaited(_attemptReconnect());
    });
  }

  /// socket 死亡 / 心跳超时后的自动重连调度：先发一条 willRetry=true 的
  /// disconnected（UI 置灰连接态但不弹提示），然后沿重试梯静默重试。
  void _scheduleAutoReconnect(String reason) {
    _autoReconnectTimer?.cancel();
    if (_events.isClosed) return;
    _events.add(RtEvent(RtEventKind.disconnected, reason, true));
    _retryRound = 0;
    _scheduleNextRetry();
  }

  /// 心跳判死 / 远端关闭的统一善后：停心跳、拆干净 socket、进重试梯。
  void _handleDeadSocket(String reason) {
    _pingTimer?.cancel();
    _pingTimer = null;
    unawaited(_wsSub?.cancel());
    _wsSub = null;
    _ws = null;
    _scheduleAutoReconnect(reason);
  }

  /// 启动应用层心跳：注册完成后调用。每 [_kPingInterval] 发一笔 ping，
  /// 超过 [_kPingDeadLine] 没收到任何入站帧即判死（半开连接的唯一可靠探针）。
  void _startHeartbeat() {
    _pingTimer?.cancel();
    _lastPongAt = DateTime.now();
    _pingTimer = Timer.periodic(_kPingInterval, (_) {
      if (_ws == null) {
        _pingTimer?.cancel();
        return;
      }
      final silent = DateTime.now().difference(_lastPongAt);
      if (silent >= _kPingDeadLine) {
        // 半开：本地以为活着、对端早已不在。主动拆掉触发重连梯。
        _handleDeadSocket('心跳超时（${silent.inSeconds}s 无响应）');
        return;
      }
      _sendJson({'type': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch});
    });
  }

  /// 打开 WS 并完成注册握手——connect / reconnect 共用的传输层重建段。
  /// 幂等：先拆掉旧 socket（半死连接也要拆干净）再开新的。
  Future<void> _openSocketAndRegister() async {
    _registerTimeout?.cancel();
    _autoReconnectTimer?.cancel(); // 新 socket 打开：待发的自动重连作废
    _pingTimer?.cancel();
    _pingTimer = null;
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
    _wsSub = channel.stream.listen(
      _onFrame,
      onDone: () {
        // 死亡即置空：isConnected 的真相来源，重进/回前台的补连判断靠它。
        // 不直接发 disconnected——先进重试梯，全部失败才报最终断开。
        _handleDeadSocket('连接关闭');
      },
      onError: (Object e) {
        // 错误通常紧随 onDone；同样只调度重连，不直接弹错误。
        _handleDeadSocket('连接错误：$e');
      },
    );

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
    _startHeartbeat();
  }

  void _onFrame(dynamic raw) {
    // 任何入站帧都证明管道活着（pong / ack / welcome / registered 同等有效）
    _lastPongAt = DateTime.now();
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
          _events.add(
            RtEvent(RtEventKind.deliveryFailed, '投递失败：${msg['status']}'),
          );
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
      final plain = await rtOpen(
        key: derived.keyPcToPhone,
        aad: rtBuildAad(derived.room, kRtDirPcToPhone, ackSeq),
        envelope: ack,
      );
      _e2eConfirmed = true;
      _events.add(RtEvent(RtEventKind.e2eConfirmed));
      // 图片通道靠 applied_seq 逐块对账（缺 ack 时按 seq 补发），这里必须有值
      final applied = (plain['applied_seq'] as num?)?.toInt();
      if (applied != null && !_ackApplied.isClosed) {
        _ackApplied.add(applied);
      }
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

  /// 发送一条鼠标事件（v0.6.0+ 触摸板协议），形状见 [rtMousePlaintext]。
  ///
  /// 与 [syncHotkey] 同属事件语义、共用 seq 域与加密路径；差异：PC 端不回
  /// ACK（高频通道），发送失败不重试——移动增量下一帧自愈，点击重发有
  /// 误双击风险（宁少勿多）。调用方按 ~30Hz 合批后调用，勿逐帧发。
  ///
  /// 返回 true = 信封已实际发出（WS 未连接返回 false）。
  Future<bool> syncMouse(Map<String, dynamic> mouse) async {
    if (mouse.isEmpty) return false;
    final derived = await _derivedFuture;
    if (_ws == null) return false;
    _seq += 1;
    final envelope = await rtSeal(
      key: derived.keyPhoneToPc,
      aad: rtBuildAad(derived.room, kRtDirPhoneToPc, _seq),
      plaintext: rtMousePlaintext(
        mouse,
        DateTime.now().millisecondsSinceEpoch,
        _phoneId,
      ),
      sid: _sid,
      seq: _seq,
    );
    _sendJson({'clientId': _target, 'text': jsonEncode(envelope)});
    return true;
  }

  /// 发送一条虚拟手柄指令（v0.7.0+ vpad_* 协议），形状见 [rtVpadPlaintext]。
  ///
  /// 与 [syncHotkey]/[syncMouse] 同属事件语义、共用 seq 域与加密路径，PC 端
  /// 不回 ACK；保序由 PC 端 vpad 专用串行链保证（press/release 不会乱序）。
  ///
  /// 返回 true = 信封已实际发出（WS 未连接返回 false）。
  Future<bool> syncVpad(Map<String, dynamic> cmd) async {
    if (cmd.isEmpty) return false;
    final derived = await _derivedFuture;
    if (_ws == null) return false;
    _seq += 1;
    final envelope = await rtSeal(
      key: derived.keyPhoneToPc,
      aad: rtBuildAad(derived.room, kRtDirPhoneToPc, _seq),
      plaintext: rtVpadPlaintext(
        cmd,
        DateTime.now().millisecondsSinceEpoch,
        _phoneId,
      ),
      sid: _sid,
      seq: _seq,
    );
    _sendJson({'clientId': _target, 'text': jsonEncode(envelope)});
    return true;
  }

  /// 发送一条图片传输指令（v0.8.0+ 文件模块·实时拍照协议），形状见
  /// [rtImagePlaintext]。与事件族共用 seq 域与加密路径；与 hotkey/mouse 的
  /// 差异：**逐条回 ACK**——begin/chunk 的 ACK = 分片落袋（续传对账依据），
  /// end 的 ACK = 整图已进剪贴板（唯一成功信号）。分片编排与进度见
  /// [RtImageTransfer]，本方法只管单条信封。
  ///
  /// 返回本条信封的 p2c seq（ACK 对账要用）；WS 未连接返回 null。
  Future<int?> syncImageOp(Map<String, dynamic> img) async {
    if (img.isEmpty) return null;
    final derived = await _derivedFuture;
    if (_ws == null) return null;
    _seq += 1;
    final seq = _seq;
    final envelope = await rtSeal(
      key: derived.keyPhoneToPc,
      aad: rtBuildAad(derived.room, kRtDirPhoneToPc, seq),
      plaintext: rtImagePlaintext(
        img,
        DateTime.now().millisecondsSinceEpoch,
        _phoneId,
      ),
      sid: _sid,
      seq: seq,
    );
    _sendJson({'clientId': _target, 'text': jsonEncode(envelope)});
    return seq;
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
    _autoReconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _wsSub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    await _events.close();
    await _ackApplied.close();
  }
}

final Random _rng = Random.secure();

String _randomHex(int bytes) => List<int>.generate(
  bytes,
  (_) => _rng.nextInt(256),
).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
