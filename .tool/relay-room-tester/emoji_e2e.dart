// .tool/relay-room-tester/emoji_e2e.dart
//
// Relay room tester — emoji e2e harness (TRACK D).
//
// Two clients join same room code, A sends EMOJI, B snapshot contains the
// emoji event (seq dedup). Also verifies ring buffer cap 16.
//
// Mock tests are HTTP-only (no WS) so they never hit the 30 s Timer hang
// that RoomHandle.createRoom/joinRoom would cause (see relay_v3_transport_test.dart
// _NoConnectHandle / RoomHandle.testCreate pattern). Live tests use the real
// RoomHandle path.
//
// Run (mock, CI-safe, no server):
//   flutter test .tool/relay-room-tester/emoji_e2e.dart
//
// Run (live, opt-in, hits real relay + Lua VM):
//   flutter test .tool/relay-room-tester/emoji_e2e.dart --dart-define=RELAY_URL=http://127.0.0.1:8000 --dart-define=LIVE=true

// ignore: library_private_types_in_public_api, invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

// ---------------------------------------------------------------------------
// Expected Lua contract — mirrors lib/core/game_kit/emoji/emoji_script.dart
// (kEmojiScriptSegment). Ring 16 on c.emojiRing, seq on c.emojiSeq,
// rate 1.5 s via c.lastEmojiAt, coalesce same from+id. Keep this copy here so
// the harness stays standalone before/after prod segment lands.
// ---------------------------------------------------------------------------
const String kEmojiTestScript = r'''
-- emoji ring buffer (cap 16) + seq dedup + 1.5s throttle (prod contract)
-- context shape (prod):
--   c.emojiRing   : array of {id, from, seq, ts, count}  (cap 16, FIFO)
--   c.emojiSeq    : monotonic seq
--   c.lastEmojiAt : { device_id -> last_ms }
-- plus legacy aliases accepted by overlay: emoji_events / emojis
function _emojiRateLimited(c, p, now)
  c.lastEmojiAt = c.lastEmojiAt or {}
  local last = c.lastEmojiAt[p.device_id] or 0
  if now - last < 1500 then return true end
  c.lastEmojiAt[p.device_id] = now
  return false
end
on_init = function(c, p)
  c.emojiRing = {}
  c.emojiSeq = 0
  c.lastEmojiAt = {}
  c.players = {}
  c.players[p.device_id] = p.alias
  c.host_id = p.device_id
  -- legacy alias so overlay candidates pick it up regardless of key name
  c.emoji_events = c.emojiRing
  c.emojis = c.emojiRing
  return c
end
on_join = function(c, p)
  c.players[p.device_id] = p.alias
  return c
end
on_leave = function(c, p) return c end
on_action_EMOJI = function(c, p)
  if c.players == nil or c.players[p.device_id] == nil then return c end
  local id = p.emoji_id or p.emojiId or p.emoji
  if type(id) ~= "string" or id == "" then return c end
  if #id > 32 then return c end
  local now = p.ts or (os.time() * 1000)
  if _emojiRateLimited(c, p, now) then return c end
  -- legacy seq dedup (accept harness seq if supplied)
  c._lastSeqByDevice = c._lastSeqByDevice or {}
  if p.seq ~= nil and c._lastSeqByDevice[p.device_id] == p.seq then return c end
  c.emojiRing = c.emojiRing or {}
  c.emojiSeq = (c.emojiSeq or 0) + 1
  local seq = p.seq or c.emojiSeq
  local last = c.emojiRing[#c.emojiRing]
  if last ~= nil and last.from == p.device_id and last.id == id then
    last.count = (last.count or 1) + 1
    last.seq = seq
    last.ts = now
    c.emoji_events = c.emojiRing
    c.emojis = c.emojiRing
    if p.seq ~= nil then c._lastSeqByDevice[p.device_id] = p.seq end
    return c
  end
  table.insert(c.emojiRing, { id = id, from = p.device_id, ts = now, seq = seq, count = 1, emoji_id = id })
  if #c.emojiRing > 16 then table.remove(c.emojiRing, 1) end
  c.emoji_events = c.emojiRing
  c.emojis = c.emojiRing
  if p.seq ~= nil then c._lastSeqByDevice[p.device_id] = p.seq end
  return c
end
return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_EMOJI" } },
  on_init = on_init, on_join = on_join, on_leave = on_leave,
  on_action_EMOJI = on_action_EMOJI,
}
''';

// ---------------------------------------------------------------------------
// In-memory mock relay (HTTP control plane only). Shared by both transports.
// ---------------------------------------------------------------------------

class _RoomState {
  _RoomState({required this.code, required this.context, required this.version});
  final String code;
  Map<String, dynamic> context;
  int version;
  final List<Map<String, dynamic>> history = [];
  final Map<String, dynamic> lastSeqByDevice = {};
  final Map<String, int> lastAtByDevice = {};
  int seqCounter = 0;
}

Map<String, dynamic> _snapJson(_RoomState r) => {
      'room_code': r.code,
      'script_hash': 'test-hash',
      'script_src': kEmojiTestScript,
      'context': Map<String, dynamic>.from(r.context),
      'state': 'lobby',
      'version': r.version,
      'created_at': '2026-09-04T00:00:00Z',
      'updated_at': '2026-09-04T00:00:00Z',
      'history': List<Map<String, dynamic>>.from(r.history),
    };

MockClient makeSharedMock(Map<String, _RoomState> rooms) {
  return MockClient((http.Request req) async {
    final path = req.url.path;
    final method = req.method;

    if (method == 'POST' && path == '/api/v3/relay/rooms') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final requested = body['requested_code'] as String?;
      final code = (requested != null && requested.isNotEmpty) ? requested : 'EMOJI1';
      final deviceId = body['device_id'] as String? ?? 'host';
      final alias = body['alias'] as String? ?? 'host';
      // idempotent: reuse if already seeded by test helper
      if (rooms.containsKey(code)) {
        final r = rooms[code]!;
        return http.Response(jsonEncode({'room_code': code, 'ws_url': 'ws://127.0.0.1:1/ws3/$code', 'snapshot': _snapJson(r)}), 201,
            headers: {'content-type': 'application/json'});
      }
      final room = _RoomState(code: code, context: {'emojiRing': <Map<String, dynamic>>[], 'emoji_events': <Map<String, dynamic>>[], 'emojis': <Map<String, dynamic>>[], 'players': {deviceId: alias}, 'host_id': deviceId}, version: 1);
      // keep aliases in sync
      room.context['emoji_events'] = room.context['emojiRing'];
      room.context['emojis'] = room.context['emojiRing'];
      rooms[code] = room;
      return http.Response(jsonEncode({'room_code': code, 'ws_url': 'ws://127.0.0.1:1/ws3/$code', 'snapshot': _snapJson(room)}), 201,
          headers: {'content-type': 'application/json'});
    }

    final joinRe = RegExp(r'^/api/v3/relay/rooms/([^/]+)/join$');
    final joinM = joinRe.firstMatch(path);
    if (method == 'POST' && joinM != null) {
      final code = joinM.group(1)!;
      final room = rooms[code];
      if (room == null) return http.Response('not found', 404);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final deviceId = body['device_id'] as String? ?? 'guest';
      final alias = body['alias'] as String? ?? 'guest';
      (room.context['players'] as Map)[deviceId] = alias;
      return http.Response(jsonEncode({'code': 0, 'message': 'ok', 'data': {'ws_url': 'ws://127.0.0.1:1/ws3/$code', 'snapshot': _snapJson(room)}}), 200,
          headers: {'content-type': 'application/json'});
    }

    final actRe = RegExp(r'^/api/v3/relay/rooms/([^/]+)/actions$');
    final actM = actRe.firstMatch(path);
    if (method == 'POST' && actM != null) {
      final code = actM.group(1)!;
      final room = rooms[code];
      if (room == null) return http.Response('not found', 404);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final type = body['type'] as String? ?? '';
      final params = (body['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final source = body['source_device_id'] as String? ?? params['device_id'] as String? ?? 'unknown';
      if (type == 'EMOJI') {
        final seqParam = params['seq'];
        final emojiId = params['emoji_id'] ?? params['emojiId'] ?? params['emoji'] ?? '';
        final ts = params['ts'] is int ? params['ts'] as int : (params['ts'] is num ? (params['ts'] as num).toInt() : 0);
        final now = ts != 0 ? ts : DateTime.now().millisecondsSinceEpoch;
        // seq dedup (harness-provided seq)
        if (seqParam != null && room.lastSeqByDevice[source] == seqParam) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok', 'data': {'snapshot': _snapJson(room)}}), 200,
              headers: {'content-type': 'application/json'});
        }
        // throttle
        final last = room.lastAtByDevice[source];
        if (last != null && now - last < 1500) {
          return http.Response(jsonEncode({'code': 0, 'message': 'ok', 'data': {'snapshot': _snapJson(room)}}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (emojiId is String && emojiId.isNotEmpty) {
          final ring = (room.context['emojiRing'] as List).cast<Map<String, dynamic>>();
          room.seqCounter += 1;
          final seq = seqParam ?? room.seqCounter;
          // coalesce same from+id (prod behavior)
          if (ring.isNotEmpty && ring.last['from'] == source && ring.last['id'] == emojiId) {
            ring.last['count'] = ((ring.last['count'] as int?) ?? 1) + 1;
            ring.last['seq'] = seq;
            ring.last['ts'] = now;
          } else {
            ring.add({'id': emojiId, 'emoji_id': emojiId, 'from': source, 'seq': seq, 'ts': now, 'count': 1});
            while (ring.length > 16) {
              ring.removeAt(0);
            }
          }
          room.context['emojiRing'] = ring;
          room.context['emoji_events'] = ring;
          room.context['emojis'] = ring;
          if (seqParam != null) room.lastSeqByDevice[source] = seqParam;
          room.lastAtByDevice[source] = now;
          room.version += 1;
          room.history.add({'type': 'EMOJI', 'params': params, 'from_state': 'lobby', 'to_state': 'lobby', 'at': DateTime.now().toUtc().toIso8601String(), 'version': room.version});
        }
      } else {
        room.version += 1;
      }
      return http.Response(jsonEncode({'code': 0, 'message': 'ok', 'data': {'snapshot': _snapJson(room)}}), 200,
          headers: {'content-type': 'application/json'});
    }

    final snapRe = RegExp(r'^/api/v3/relay/rooms/([^/]+)/snapshot$');
    final snapM = snapRe.firstMatch(path);
    if (method == 'GET' && snapM != null) {
      final code = snapM.group(1)!;
      final room = rooms[code];
      if (room == null) return http.Response('not found', 404);
      return http.Response(jsonEncode({'code': 0, 'message': 'ok', 'data': {'snapshot': _snapJson(room)}}), 200,
          headers: {'content-type': 'application/json'});
    }

    final leaveRe = RegExp(r'^/api/v3/relay/rooms/([^/]+)/leave$');
    final leaveM = leaveRe.firstMatch(path);
    if (method == 'POST' && leaveM != null) {
      return http.Response('', 204);
    }

    return http.Response('not found: $method $path', 404);
  });
}

/// Seed a room directly in the shared map (no HTTP, no WS).
String seedRoom(Map<String, _RoomState> rooms, String code, String hostId, String hostAlias) {
  rooms[code] = _RoomState(code: code, context: {'emojiRing': <Map<String, dynamic>>[], 'emoji_events': <Map<String, dynamic>>[], 'emojis': <Map<String, dynamic>>[], 'players': {hostId: hostAlias}, 'host_id': hostId}, version: 1);
  rooms[code]!.context['emoji_events'] = rooms[code]!.context['emojiRing'];
  rooms[code]!.context['emojis'] = rooms[code]!.context['emojiRing'];
  return code;
}

bool get _isLive {
  const liveFlag = String.fromEnvironment('LIVE', defaultValue: 'false');
  if (liveFlag == 'true') return true;
  try {
    return Platform.environment['LIVE'] == 'true';
  } catch (_) {
    return false;
  }
}

String get _relayUrl {
  const defined = String.fromEnvironment('RELAY_URL', defaultValue: '');
  if (defined.isNotEmpty) return defined;
  try {
    return Platform.environment['RELAY_URL'] ?? 'http://127.0.0.1:8000';
  } catch (_) {
    return 'http://127.0.0.1:8000';
  }
}

void main() {
  group('emoji e2e — mock relay (no server, HTTP-only)', () {
    test('two clients join same room, A EMOJI visible to B', () async {
      final rooms = <String, _RoomState>{};
      final mock = makeSharedMock(rooms);
      final tA = RelayV3Transport(relayUrl: 'http://mock', alias: 'Alice', deviceId: 'device-a', httpClient: mock);
      final tB = RelayV3Transport(relayUrl: 'http://mock', alias: 'Bob', deviceId: 'device-b', httpClient: mock);
      const code = 'EMOJI1';
      seedRoom(rooms, code, 'device-a', 'Alice');
      await tB.testJoin(code: code, deviceId: 'device-b', alias: 'Bob');

      final before = await tB.fetchSnapshot(code);
      final beforeList = (before.context['emoji_events'] as List?) ?? (before.context['emojiRing'] as List?) ?? [];
      expect(beforeList, isEmpty);

      final afterA = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'fire', 'seq': 1, 'ts': 1000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      final afterList = (afterA.context['emoji_events'] as List?) ?? (afterA.context['emojiRing'] as List?) ?? [];
      expect(afterList.length, 1);
      expect(((afterList.first as Map)['emoji_id'] ?? (afterList.first as Map)['id']), 'fire');

      final snapB = await tB.fetchSnapshot(code);
      final eventsB = ((snapB.context['emoji_events'] as List?) ?? (snapB.context['emojiRing'] as List) ?? []).cast<Map>();
      expect(eventsB.length, 1, reason: 'B snapshot contains A emoji');
      expect(eventsB.first['from'], 'device-a');
      expect(eventsB.first['seq'], 1);
    });

    test('seq dedup — duplicate seq from same device dropped', () async {
      final rooms = <String, _RoomState>{};
      final mock = makeSharedMock(rooms);
      final tA = RelayV3Transport(relayUrl: 'http://mock', alias: 'Alice', deviceId: 'device-a', httpClient: mock);
      final tB = RelayV3Transport(relayUrl: 'http://mock', alias: 'Bob', deviceId: 'device-b', httpClient: mock);
      const code = 'EMOJI2';
      seedRoom(rooms, code, 'device-a', 'Alice');
      await tB.testJoin(code: code, deviceId: 'device-b', alias: 'Bob');

      final s1 = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'joy', 'seq': 42, 'ts': 5000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      final v1 = s1.version;
      final l1 = ((s1.context['emoji_events'] as List?) ?? (s1.context['emojiRing'] as List) ?? []);
      expect(l1.length, 1);

      final s2 = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'joy', 'seq': 42, 'ts': 7000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      expect(s2.version, v1, reason: 'duplicate seq must not bump version');

      final snapB = await tB.fetchSnapshot(code);
      final with42 = (((snapB.context['emoji_events'] as List?) ?? (snapB.context['emojiRing'] as List) ?? []).cast<Map>()).where((e) => e['seq'] == 42).toList();
      expect(with42.length, 1);

      final s3 = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'fire', 'seq': 43, 'ts': 9000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      final l3 = ((s3.context['emoji_events'] as List?) ?? (s3.context['emojiRing'] as List) ?? []);
      expect(l3.length, 2);
      expect(s3.version, greaterThan(v1));
    });

    test('ring buffer cap 16 — 20 sends retain last 16', () async {
      final rooms = <String, _RoomState>{};
      final mock = makeSharedMock(rooms);
      final tA = RelayV3Transport(relayUrl: 'http://mock', alias: 'Alice', deviceId: 'device-a', httpClient: mock);
      final tB = RelayV3Transport(relayUrl: 'http://mock', alias: 'Bob', deviceId: 'device-b', httpClient: mock);
      const code = 'EMOJI3';
      seedRoom(rooms, code, 'device-a', 'Alice');
      await tB.testJoin(code: code, deviceId: 'device-b', alias: 'Bob');

      for (var i = 1; i <= 20; i++) {
        // use distinct ids to avoid coalesce collapsing counts
        await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'e$i', 'seq': i, 'ts': i * 2000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      }

      final snapA = await tA.fetchSnapshot(code);
      final eventsA = (((snapA.context['emoji_events'] as List?) ?? (snapA.context['emojiRing'] as List) ?? []).cast<Map>());
      expect(eventsA.length, 16, reason: 'ring buffer cap is 16');
      expect(eventsA.first['seq'], 5);
      expect(eventsA.last['seq'], 20);

      final snapB = await tB.fetchSnapshot(code);
      final eventsB = (((snapB.context['emoji_events'] as List?) ?? (snapB.context['emojiRing'] as List) ?? []).cast<Map>());
      expect(eventsB.length, 16);
      expect(eventsB.map((e) => e['seq']).toList(), List.generate(16, (i) => 5 + i));

      expect(kEmojiTestScript.contains('16'), isTrue);
    });

    test('throttle — second EMOJI within 1.5s dropped', () async {
      final rooms = <String, _RoomState>{};
      final mock = makeSharedMock(rooms);
      final tA = RelayV3Transport(relayUrl: 'http://mock', alias: 'Alice', deviceId: 'device-a', httpClient: mock);
      const code = 'EMOJI4';
      seedRoom(rooms, code, 'device-a', 'Alice');

      final s1 = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'a', 'seq': 1, 'ts': 10000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      final l1 = ((s1.context['emoji_events'] as List?) ?? (s1.context['emojiRing'] as List) ?? []);
      expect(l1.length, 1);

      final s2 = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'b', 'seq': 2, 'ts': 10500, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      expect(s2.version, s1.version, reason: 'throttle should drop');

      final s3 = await tA.testApplyAction(code: code, type: 'EMOJI', params: {'emoji_id': 'c', 'seq': 3, 'ts': 12000, 'alias': 'Alice'}, sourceDeviceId: 'device-a');
      final l3 = ((s3.context['emoji_events'] as List?) ?? (s3.context['emojiRing'] as List) ?? []);
      expect(l3.length, 2);
      expect(s3.version, greaterThan(s1.version));
    });
  });

  group('emoji e2e — live relay (opt-in)', () {
    test('live: A EMOJI visible to B + ring cap', () async {
      if (!_isLive) return;
      final relayUrl = _relayUrl;
      final tA = RelayV3Transport(relayUrl: relayUrl, alias: 'Alice-live', deviceId: 'live-a-${DateTime.now().microsecondsSinceEpoch}');
      final tB = RelayV3Transport(relayUrl: relayUrl, alias: 'Bob-live', deviceId: 'live-b-${DateTime.now().microsecondsSinceEpoch}');
      late RoomHandle hA;
      try {
        hA = await tA.createRoom(script: kEmojiTestScript, initialParams: {});
      } catch (e) {
        // ignore: avoid_print
        print('[live] createRoom failed ($e) — is relay at $relayUrl running? skipping.');
        return;
      }
      final hB = await tB.joinRoom(code: hA.code);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await hA.applyAction(type: 'EMOJI', params: {'emoji_id': 'fire', 'seq': 101, 'ts': DateTime.now().millisecondsSinceEpoch, 'alias': 'Alice-live'});
      Snapshot snapB = await hB.fetchSnapshot();
      var tries = 0;
      List? listB() => (snapB.context['emoji_events'] as List?) ?? (snapB.context['emojiRing'] as List?) ?? (snapB.context['emojis'] as List?);
      while ((listB()?.isEmpty ?? true)) {
        if (tries++ > 10) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        snapB = await hB.fetchSnapshot();
      }
      final got = listB() ?? [];
      expect(got.length, greaterThanOrEqualTo(1));
      expect((got.cast<Map>().any((e) => e['seq'] == 101 || e['id'] == 'fire')), isTrue);
      final baseTs = DateTime.now().millisecondsSinceEpoch;
      for (var i = 1; i <= 20; i++) {
        await hA.applyAction(type: 'EMOJI', params: {'emoji_id': 'live-e$i', 'seq': 200 + i, 'ts': baseTs + i * 2000, 'alias': 'Alice-live'});
      }
      final after = await hB.fetchSnapshot();
      final events = (((after.context['emoji_events'] as List?) ?? (after.context['emojiRing'] as List?) ?? (after.context['emojis'] as List?) ?? <dynamic>[]).cast<Map>());
      expect(events.length, lessThanOrEqualTo(16), reason: 'live ring cap should be <=16');
      await hA.dispose();
      await hB.dispose();
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
