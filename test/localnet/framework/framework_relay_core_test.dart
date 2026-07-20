import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_relay_core.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

class _MockHttp extends http.BaseClient {
  final Map<String, http.Response Function(http.Request)> handlers = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    final handler = handlers['${req.method}:${req.url.path}'];
    if (handler == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"not mocked"}')),
        404,
      );
    }
    final resp = handler(req as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

void main() {
  test('FrameworkRelayCore.start initializes all managers', () async {
    final mockHttp = _MockHttp();
    mockHttp.handlers['POST:/api/v1/relay/rooms'] = (req) => http.Response(
          jsonEncode({'roomCode': '111111', 'wsUrl': 'wss://relay.example.com/ws/111111'}),
          201,
        );

    final core = FrameworkRelayCore(
      config: const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self-id',
        deviceAlias: 'Self',
      ),
      roomEndpoint: RoomEndpoint(
        baseUrl: 'https://relay.example.com',
        httpClient: mockHttp,
      ),
    );

    await core.start();
    expect(core.isRunning, isTrue);
    expect(core.discovery, isNotNull);
    expect(core.deviceManager, isNotNull);
    expect(core.channelManager, isNotNull);
    expect(core.sessionManager, isNotNull);
    expect(core.eventBus, isNotNull);
    await core.stop();
  });

  test('FrameworkRelayCore.createRoom returns room code', () async {
    final mockHttp = _MockHttp();
    mockHttp.handlers['POST:/api/v1/relay/rooms'] = (req) => http.Response(
          jsonEncode({'roomCode': '222222', 'wsUrl': 'wss://relay.example.com/ws/222222'}),
          201,
        );

    final core = FrameworkRelayCore(
      config: const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self-id',
        deviceAlias: 'Self',
      ),
      roomEndpoint: RoomEndpoint(
        baseUrl: 'https://relay.example.com',
        httpClient: mockHttp,
      ),
    );

    await core.start();
    // 仅验证 discovery.createRoom 工作（mock 工作即可，不实际连 WS）
    final info = await core.discovery.createRoom();
    expect(info, '222222');
    await core.stop();
  });
}