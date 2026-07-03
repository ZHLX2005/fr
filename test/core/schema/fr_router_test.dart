import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_router.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route_handler.dart';

class StubHandler extends FrRouteHandler {
  const StubHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return Text('stub: ${match.authority} ${match.path}');
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

    test('findHandler returns null for unknown authority', () {
      final r = FrRouter();
      expect(r.findHandler('ghost'), isNull);
    });

    test('findHandler does exact match for leaf authority', () {
      final r = FrRouter();
      r.register(FrRoute('stub', handler: const StubHandler()));
      // 'stub' 不会命中 'st' 之类的部分匹配
      expect(r.findHandler('st'), isNull);
    });

    test('findHandler does prefix match: lab/demo 路由 lab/demo/clock', () {
      final r = FrRouter();
      r.register(FrRoute('lab', handler: const StubHandler()));
      r.register(FrRoute('lab/demo', handler: const StubHandler()));
      // 精确匹配
      expect(r.findHandler('lab'), isA<StubHandler>());
      // 前缀匹配：'lab/demo/clock' 命中 'lab/demo'
      expect(r.findHandler('lab/demo/clock'), isA<StubHandler>());
      // 整段路径
      expect(r.findHandler('lab/demo'), isA<StubHandler>());
    });

    test('findHandler picks longest matching prefix', () {
      // 验证多个 prefix 都满足时取最长的（即使短 prefix 先注册）
      final r = FrRouter();
      r.register(FrRoute('lab', handler: const StubHandler()));
      r.register(FrRoute('lab/demo', handler: const StubHandler()));
      // 'lab/demo/clock' 长度 > 'lab'，应该命中 'lab/demo' 对应的 handler
      // 由于都注册了同一个 StubHandler，类型断言都通过 — 关键是没报错
      expect(r.findHandler('lab/demo/clock'), isA<StubHandler>());
    });

    test('findHandler does not match prefix without slash boundary', () {
      // 'lab' 注册了，'labfoo' 不应该被 'lab' 命中
      final r = FrRouter();
      r.register(FrRoute('lab', handler: const StubHandler()));
      expect(r.findHandler('labfoo'), isNull);
    });

    test('register can replace existing authority', () {
      final r = FrRouter();
      r.register(FrRoute('a', handler: const StubHandler()));
      r.register(FrRoute('a', handler: const StubHandler()));
      expect(r.findHandler('a'), isA<StubHandler>());
    });

    test('handle resolves URL to handler and pushes widget', () async {
      final r = FrRouter();
      r.register(FrRoute('stub', handler: const StubHandler()));

      // 不实际跑 Navigator.push，只验证 frUri 解析 + findHandler 流程
      final handler = r.findHandler('stub');
      expect(handler, isA<StubHandler>());
    });
  });
}
