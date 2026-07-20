import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_frame.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/ws_transport.dart';

class _FakeChannel implements WebSocketChannel {
  final _in = StreamController<dynamic>.broadcast();
  final _out = StreamController<String>.broadcast();
  final List<String> sent = [];
  bool closed = false;

  @override
  String? get protocol => '';

  @override
  int? get closeCode => 0;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  @override
  Stream get stream => _in.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  void pipe(StreamChannel other) {}

  @override
  StreamChannel<S> cast<S>() => throw UnimplementedError();

  void push(String text) => _in.add(text);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._ch);
  final _FakeChannel _ch;

  @override
  void add(dynamic event) {
    _ch.sent.add(event as String);
  }

  @override
  void addError(Object error, [StackTrace? st]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {
    _ch.closed = true;
  }

  @override
  Future get done => Future.value();
}

void main() {
  test('WsTransport parses incoming frames', () async {
    final fake = _FakeChannel();
    final transport = WsTransport(channel: fake, myDeviceId: 'self');
    final received = <TransportFrame>[];
    final sub = transport.frames.listen(received.add);

    fake.push(jsonEncode({
      'channelName': 'chat',
      'sourceDeviceId': 'peer',
      'payload': 'aGVsbG8=', // 'hello'
      'timestamp': '2026-07-20T12:00:00Z',
    }));
    await Future.delayed(const Duration(milliseconds: 10));
    expect(received, hasLength(1));
    expect(received.first.sourceDeviceId, 'peer');
    expect(String.fromCharCodes(received.first.payload), 'hello');
    await sub.cancel();
    await transport.close();
  });

  test('WsTransport.send emits frame as JSON', () async {
    final fake = _FakeChannel();
    final transport = WsTransport(channel: fake, myDeviceId: 'self');
    await transport.send(TransportFrame(
      channelName: 'chat',
      sourceDeviceId: 'self',
      payload: Uint8List.fromList(utf8.encode('hi')),
      timestamp: DateTime.now(),
    ));
    await Future.delayed(const Duration(milliseconds: 10));
    expect(fake.sent, hasLength(1));
    final json = jsonDecode(fake.sent.first) as Map<String, dynamic>;
    expect(json['channelName'], 'chat');
    expect(String.fromCharCodes(base64Decode(json['payload'] as String)), 'hi');
    await transport.close();
  });
}