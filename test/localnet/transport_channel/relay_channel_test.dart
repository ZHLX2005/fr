import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_frame.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/ws_transport.dart';
import 'package:xiaodouzi_fr/core/localnet/transport_channel/relay_channel.dart';

class _FakeChannel implements WebSocketChannel {
  final _in = StreamController<dynamic>.broadcast();
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
  test('RelayChannel.send routes frame via WsTransport', () async {
    final fake = _FakeChannel();
    final ws = WsTransport(channel: fake, myDeviceId: 'self');
    final channel = RelayChannel(ws: ws, myDeviceId: 'self');

    await channel.open(channelName: 'surround/game/state', remoteDeviceId: 'peer');
    await channel.send('surround/game/state', Uint8List.fromList(utf8.encode('hello')));
    await Future.delayed(const Duration(milliseconds: 10));

    expect(fake.sent, hasLength(1));
    final json = jsonDecode(fake.sent.first) as Map<String, dynamic>;
    expect(json['channelName'], 'surround/game/state');
    expect(String.fromCharCodes(base64Decode(json['payload'] as String)), 'hello');

    await channel.close();
  });

  test('RelayChannel.watch filters incoming frames by channelName', () async {
    final fake = _FakeChannel();
    final ws = WsTransport(channel: fake, myDeviceId: 'self');
    final channel = RelayChannel(ws: ws, myDeviceId: 'self');

    await channel.open(channelName: 'chat', remoteDeviceId: 'peer');
    final received = <TransportFrame>[];
    final sub = channel.watch('chat').listen(received.add);

    fake.push(jsonEncode({
      'channelName': 'other',
      'sourceDeviceId': 'p',
      'payload': 'aGk=', // 'hi'
      'timestamp': '2026-07-20T12:00:00Z',
    }));
    fake.push(jsonEncode({
      'channelName': 'chat',
      'sourceDeviceId': 'p',
      'payload': 'aGVsbG8=', // 'hello'
      'timestamp': '2026-07-20T12:00:01Z',
    }));
    await Future.delayed(const Duration(milliseconds: 20));

    expect(received, hasLength(1));
    expect(received.first.channelName, 'chat');
    expect(String.fromCharCodes(received.first.payload), 'hello');

    await sub.cancel();
    await channel.close();
  });
}