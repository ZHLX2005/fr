import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/event_bus.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/lan_event.dart';

void main() {
  group('EventBus', () {
    test('emit 后 watchAll 应收到事件', () async {
      final bus = EventBus();
      final received = <LanEvent>[];
      final sub = bus.watchAll().listen(received.add);

      bus.emit(ServiceStartedEvent());

      // 给异步 Stream 一个微任务
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(received.first, isA<ServiceStartedEvent>());

      await sub.cancel();
      bus.dispose();
    });

    test('watch<T> 过滤器只返回指定类型', () async {
      final bus = EventBus();
      final received = <ServiceStartedEvent>[];
      final sub = bus.watch<ServiceStartedEvent>().listen(received.add);

      bus.emit(ServiceStartedEvent());
      bus.emit(ServiceStoppedEvent()); // 不同类型

      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);

      await sub.cancel();
      bus.dispose();
    });

    test('dispose 后不再发射事件', () async {
      final bus = EventBus();
      bus.dispose();

      expect(() => bus.emit(ServiceStartedEvent()), throwsA(isA<StateError>()));
    });
  });
}
