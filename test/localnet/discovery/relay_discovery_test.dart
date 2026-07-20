import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';
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
      expect(result.roomCode, '123456');
      expect(result.wsUrl, contains('wss://'));
    });

    test('joinRoom throws RoomNotFoundError on 404', () async {
      mock.handlers['GET:/api/v1/rooms/999999'] = (req) =>
          http.Response('not found', 404);
      expect(
        () => discovery.joinRoom(roomCode: '999999'),
        throwsA(isA<RoomNotFoundError>()),
      );
    });

    test('joinRoom returns peer endpoint on 200', () async {
      mock.handlers['GET:/api/v1/rooms/123456'] = (req) => http.Response(
        jsonEncode({
          'roomCode': '123456',
          'hostDeviceId': 'host-id',
          'hostAlias': 'Host',
          'wsUrl': 'wss://relay.example.com/ws/123456',
        }),
        200,
      );
      final result = await discovery.joinRoom(roomCode: '123456');
      expect(result.host.deviceId, 'host-id');
      expect(result.host.alias, 'Host');
      expect(result.wsUrl, 'wss://relay.example.com/ws/123456');
    });

    test('joinRoom rejects response without wsUrl', () async {
      mock.handlers['GET:/api/v1/rooms/123456'] = (req) => http.Response(
        jsonEncode({
          'roomCode': '123456',
          'hostDeviceId': 'host-id',
          'hostAlias': 'Host',
        }),
        200,
      );

      expect(
        () => discovery.joinRoom(roomCode: '123456'),
        throwsA(isA<RelayUnreachableError>()),
      );
    });
  });
}
