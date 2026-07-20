import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/discovery_event.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/relay_discovery.dart';

class _MockHttpClient extends http.BaseClient {
  final Map<String, http.Response Function(http.Request)> handlers = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final handler = handlers['${request.method}:${request.url.path}'];
    if (handler == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"not mocked"}')),
        404,
      );
    }
    final resp = handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

void main() {
  group('RelayDiscovery', () {
    late _MockHttpClient mock;
    late RelayDiscovery discovery;

    setUp(() {
      mock = _MockHttpClient();
      final roomEndpoint = RoomEndpoint(
        baseUrl: 'https://relay.example.com',
        pathPrefix: '/api/v1',
        httpClient: mock,
      );
      discovery = RelayDiscovery(
        relayUrl: 'https://relay.example.com',
        myDeviceId: 'self-id',
        myAlias: 'Self',
        roomEndpoint: roomEndpoint,
      );
    });

    test('createRoom returns room code from server', () async {
      mock.handlers['POST:/api/v1/rooms'] = (req) => http.Response(
        jsonEncode({
          'roomCode': '123456',
          'wsUrl': 'wss://relay.example.com/ws/123456',
        }),
        201,
      );
      final result = await discovery.createRoom();
      expect(result, '123456');
    });

    test('createRoom emits RoomCreated event', () async {
      mock.handlers['POST:/api/v1/rooms'] = (req) => http.Response(
        jsonEncode({
          'roomCode': '123456',
          'wsUrl': 'wss://relay.example.com/ws/123456',
        }),
        201,
      );
      final events = <DiscoveryEvent>[];
      final sub = discovery.events.listen(events.add);
      await discovery.createRoom();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<RoomCreated>().first.roomCode, '123456');
      await sub.cancel();
    });

    test('joinRoom throws RoomNotFound on 404', () async {
      mock.handlers['POST:/api/v1/rooms/999999/join'] = (req) =>
          http.Response('not found', 404);
      final result = await discovery.joinRoom('999999');
      expect(result, isA<RoomNotFound>());
    });

    test('joinRoom returns RoomJoined on 200', () async {
      mock.handlers['POST:/api/v1/rooms/123456/join'] = (req) => http.Response(
        jsonEncode({
          'roomCode': '123456',
          'hostDeviceId': 'host-id',
          'hostAlias': 'Host',
          'wsUrl': 'wss://relay.example.com/ws/123456',
        }),
        200,
      );
      final result = await discovery.joinRoom('123456');
      expect(result, isA<RoomJoined>());
      final joined = result as RoomJoined;
      expect(joined.host.deviceId, 'host-id');
      expect(joined.host.alias, 'Host');
    });

    test('joinRoom emits event on success', () async {
      mock.handlers['POST:/api/v1/rooms/123456/join'] = (req) => http.Response(
        jsonEncode({
          'roomCode': '123456',
          'hostDeviceId': 'host-id',
          'hostAlias': 'Host',
          'wsUrl': 'wss://relay.example.com/ws/123456',
        }),
        200,
      );
      final events = <DiscoveryEvent>[];
      final sub = discovery.events.listen(events.add);
      await discovery.joinRoom('123456');
      await Future.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<RoomJoined>().first.roomCode, '123456');
      await sub.cancel();
    });
  });
}
