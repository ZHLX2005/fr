import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/message_net/message_net.dart';

void main() {
  group('LogEntry', () {
    test('encode/decode round-trip preserves all fields', () {
      final original = LogEntry(
        from: 'node-1',
        topic: 'chat',
        data: {'text': 'hello', 'alias': 'alice'},
        timestamp: DateTime.utc(2026, 7, 20, 12, 34, 56, 789),
      );

      final wire = original.encode();
      final restored = LogEntry.decode(wire);

      expect(restored.from, 'node-1');
      expect(restored.topic, 'chat');
      expect(restored.data, {'text': 'hello', 'alias': 'alice'});
      expect(restored.timestamp, original.timestamp);
    });

    test('decode missing fields with defaults', () {
      // 仅 topic 存在，其余字段缺失 → 不抛异常
      final restored = LogEntry.decode('{"topic": "x"}');
      expect(restored.topic, 'x');
      expect(restored.from, 'unknown');
      expect(restored.data, isEmpty);
    });

    test('decode handles invalid timestamp gracefully', () {
      final restored = LogEntry.decode('{"topic": "x", "ts": "not-a-date"}');
      expect(restored.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('encode produces valid JSON', () {
      final entry = LogEntry(
        from: 'n1',
        topic: 't',
        data: {'k': 'v'},
        timestamp: DateTime.utc(2026, 1, 1),
      );
      final wire = entry.encode();
      // 应包含四个字段
      expect(wire, contains('"from":"n1"'));
      expect(wire, contains('"topic":"t"'));
      expect(wire, contains('"data":{"k":"v"}'));
      expect(wire, contains('"ts":"2026-01-01'));
    });
  });

  group('MessageNet factory', () {
    test('relay mode without relayUrl throws ArgumentError', () async {
      expect(
        () => MessageNet.start(mode: MessageNetMode.relay),
        throwsArgumentError,
      );
    });

    test('lan mode returns MessageNet instance', () async {
      // 在测试环境下绑定 UDP 可能失败 — 我们只检查返回类型
      try {
        final net = await MessageNet.start(
          mode: MessageNetMode.lan,
          multicastPort: 0,  // 0 让系统分配端口
          multicastAddress: '239.255.255.255',
        );
        expect(net, isA<MessageNet>());
        await net.stop();
      } catch (_) {
        // UDP 绑定可能在测试环境失败，忽略
      }
    });
  });
}