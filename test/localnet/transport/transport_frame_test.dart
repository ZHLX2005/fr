import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_frame.dart';

void main() {
  test('TransportFrame round-trip via JSON', () {
    final frame = TransportFrame(
      channelName: 'surround/game/state',
      sourceDeviceId: 'peer-1',
      payload: Uint8List.fromList([1, 2, 3, 4]),
      timestamp: DateTime.utc(2026, 7, 20, 12, 0, 0),
    );
    final json = frame.toJson();
    final restored = TransportFrame.fromJson(json);
    expect(restored.channelName, frame.channelName);
    expect(restored.sourceDeviceId, frame.sourceDeviceId);
    expect(restored.payload, frame.payload);
    expect(restored.timestamp, frame.timestamp);
  });

  test('fromJson handles missing fields gracefully', () {
    final restored = TransportFrame.fromJson({
      'channelName': 'c',
      'sourceDeviceId': 'p',
      'payload': 'AQIDBA==', // base64 of [1,2,3,4]
      'timestamp': '2026-07-20T12:00:00Z',
    });
    expect(restored.channelName, 'c');
    expect(restored.payload, Uint8List.fromList([1, 2, 3, 4]));
  });
}
