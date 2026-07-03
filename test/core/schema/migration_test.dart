import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/schema.dart';

void main() {
  setUpAll(() {
    registerAllFrRoutes();
  });

  group('frRouter migration smoke — 严格断言具体 handler 类型', () {
    test('fr://lab → LabIndexHandler', () async {
      final match = await frRouter.resolve('fr://lab');
      expect(match, isNotNull);
      expect(match!.authority, 'lab');
      expect(match.path, '');
      // 关键：断言具体 handler 类型（不是只断言 isA<FrRouteHandler>）
      expect(frRouter.findHandler('lab'), isA<LabIndexHandler>());
    });

    test('fr://lab/demo/clock → LabDemoHandler（不是 LabIndexHandler）', () async {
      final match = await frRouter.resolve('fr://lab/demo/clock');
      expect(match, isNotNull);
      expect(match!.authority, 'lab/demo/clock');
      expect(match.path, 'demo/clock');
      // 关键：嵌套路由必须命中 LabDemoHandler，不能错命中 LabIndexHandler
      final handler = frRouter.findHandler(match.authority);
      expect(handler, isA<LabDemoHandler>());
      expect(handler, isNot(isA<LabIndexHandler>()));
    });

    test('fr://lab/core/profile → LabCoreHandler（不是 LabIndexHandler）', () async {
      final match = await frRouter.resolve('fr://lab/core/profile');
      expect(match, isNotNull);
      expect(match!.authority, 'lab/core/profile');
      expect(match.path, 'core/profile');
      final handler = frRouter.findHandler(match.authority);
      expect(handler, isA<LabCoreHandler>());
      expect(handler, isNot(isA<LabIndexHandler>()));
    });

    test('fr://lab/core/home → LabCoreHandler', () async {
      final match = await frRouter.resolve('fr://lab/core/home');
      expect(match, isNotNull);
      final handler = frRouter.findHandler(match!.authority);
      expect(handler, isA<LabCoreHandler>());
    });

    test('fr://notion/image-host?autocapture=true → NotionImageHostHandler', () async {
      final match = await frRouter.resolve('fr://notion/image-host?autocapture=true');
      expect(match, isNotNull);
      expect(match!.authority, 'notion/image-host');
      expect(match.path, 'image-host');
      expect(match.queryBool('autocapture'), isTrue);
      final handler = frRouter.findHandler(match.authority);
      expect(handler, isA<NotionImageHostHandler>());
    });

    test('fr://notion/create-page → NotionCreatePageHandler', () async {
      final match = await frRouter.resolve('fr://notion/create-page');
      expect(match, isNotNull);
      expect(match!.authority, 'notion/create-page');
      expect(match.path, 'create-page');
      final handler = frRouter.findHandler(match.authority);
      expect(handler, isA<NotionCreatePageHandler>());
    });

    test('fr://timetable → TimetableHandler', () async {
      final match = await frRouter.resolve('fr://timetable');
      expect(match, isNotNull);
      expect(match!.authority, 'timetable');
      expect(match.path, '');
      final handler = frRouter.findHandler(match.authority);
      expect(handler, isA<TimetableHandler>());
    });

    test('http://lab → null（scheme 错误）', () async {
      final match = await frRouter.resolve('http://lab');
      expect(match, isNull);
    });

    test('fr://unknown → null（未注册 authority）', () async {
      final match = await frRouter.resolve('fr://unknown');
      expect(match, isNull);
    });

    test('fr://labfoo 不会误命中 lab（无 slash 边界）', () async {
      // 防止 'lab' 前缀误匹配到 'labfoo'
      final match = await frRouter.resolve('fr://labfoo');
      expect(match, isNull);
    });
  });
}
