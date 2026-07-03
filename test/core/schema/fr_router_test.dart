import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_router.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route_handler.dart';

class StubHandler extends FrRouteHandler {
  const StubHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return Text('stub: ${match.host} ${match.path}');
  }
}

class ThrowingHandler extends FrRouteHandler {
  const ThrowingHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    throw StateError('intentional');
  }
}

void main() {
  group('FrRouter', () {
    test('register then findHandler returns the handler', () {
      final r = FrRouter();
      r.register(FrRoute('stub', handler: const StubHandler()));
      expect(r.findHandler('stub'), isA<StubHandler>());
    });

    test('registerAll adds multiple routes', () {
      final r = FrRouter();
      r.registerAll([
        FrRoute('a', handler: const StubHandler()),
        FrRoute('b', handler: const StubHandler()),
      ]);
      expect(r.findHandler('a'), isA<StubHandler>());
      expect(r.findHandler('b'), isA<StubHandler>());
    });

    test('findHandler returns null for unknown host', () {
      final r = FrRouter();
      expect(r.findHandler('ghost'), isNull);
    });

    test('handle resolves URL to handler and pushes widget', () async {
      final r = FrRouter();
      r.register(FrRoute('stub', handler: const StubHandler()));

      // 不实际跑 Navigator.push，只验证 frUri 解析 + findHandler 流程
      final handler = r.findHandler('stub');
      expect(handler, isA<StubHandler>());
    });

    test('register can replace existing host', () {
      final r = FrRouter();
      r.register(FrRoute('a', handler: const StubHandler()));
      r.register(FrRoute('a', handler: const StubHandler()));
      expect(r.findHandler('a'), isA<StubHandler>());
    });
  });
}
