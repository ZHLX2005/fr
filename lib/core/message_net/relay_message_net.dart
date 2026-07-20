import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'message_net.dart';

/// Relay 模式实现 — HTTP 房间 + WebSocket（独立实现，不复用任何已有代码）
///
/// 内部实现。业务层通过 [MessageNet.start] 获取 [MessageNet] 实例即可。
class RelayMessageNet implements MessageNet {
  RelayMessageNet._({required this.relayUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// 工厂：仅初始化 http client，连接在 [createRoom]/[joinRoom] 后建立
  static Future<RelayMessageNet> create({
    required String relayUrl,
    http.Client? httpClient,
  }) async {
    return RelayMessageNet._(relayUrl: relayUrl, httpClient: httpClient);
  }

  final String relayUrl;
  final http.Client _http;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  bool _disposed = false;

  final StreamController<LogEntry> _anyCtrl =
      StreamController<LogEntry>.broadcast();
  final Map<String, StreamController<LogEntry>> _topicCtrls = {};
  final List<LogEntry> _queue = [];

  String? _roomCode;

  @override
  String? get roomCode => _roomCode;

  String get _roomsUrl => '$relayUrl/api/v1/relay/rooms';

  @override
  Future<String?> createRoom() async {
    final resp = await _http.post(
      Uri.parse(_roomsUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'alias': '', 'deviceId': ''}),
    );
    if (resp.statusCode != 201) {
      throw _RelayException('创建房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final roomCode = json['roomCode'] as String;
    final wsUrl = json['wsUrl'] as String;
    _roomCode = roomCode;
    await _connect(wsUrl);
    return roomCode;
  }

  @override
  Future<void> joinRoom(String code) async {
    final resp = await _http.post(
      Uri.parse('$_roomsUrl/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': '', 'alias': ''}),
    );
    if (resp.statusCode == 404) {
      throw _RelayNotFoundException('房间 $code 不存在');
    }
    if (resp.statusCode == 409) {
      throw _RelayFullException('房间 $code 已满');
    }
    if (resp.statusCode != 200) {
      throw _RelayException('加入房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final wsUrl = json['wsUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      throw _RelayException('加入房间响应缺少 wsUrl');
    }
    _roomCode = code;
    await _connect(wsUrl);
  }

  Future<void> _connect(String wsUrl) async {
    final ws = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = ws;
    _wsSub = ws.stream.listen(
      _onFrame,
      onError: (_) {},  // TODO: 错误流（API 暂未暴露）
      onDone: () {},    // TODO: 重连机制
    );
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    try {
      final entry = LogEntry.decode(data);
      _dispatch(entry);
    } catch (_) {
      // 忽略非法帧
    }
  }

  void _dispatch(LogEntry entry) {
    _anyCtrl.add(entry);
    final ctrl = _topicCtrls[entry.topic];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(entry);
    }
  }

  @override
  void append(LogEntry entry) {
    final ws = _ws;
    if (ws != null) {
      // WS 已连接：立即发
      ws.sink.add(entry.encode());
    } else {
      // WS 未连接：积压（连接建立后暂不自动 flush，等业务决定）
      _queue.add(entry);
    }
  }

  @override
  Stream<LogEntry> watch(String topic) {
    return _topicCtrls
        .putIfAbsent(topic, () => StreamController<LogEntry>.broadcast())
        .stream;
  }

  @override
  Stream<LogEntry> get onAny => _anyCtrl.stream;

  @override
  void leaveRoom() {
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
    _roomCode = null;
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    leaveRoom();
    _http.close();
    await _anyCtrl.close();
    for (final c in _topicCtrls.values) {
      await c.close();
    }
    _topicCtrls.clear();
    _queue.clear();
  }
}

class _RelayException implements Exception {
  _RelayException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RelayNotFoundException extends _RelayException {
  _RelayNotFoundException(super.message);
}

class _RelayFullException extends _RelayException {
  _RelayFullException(super.message);
}