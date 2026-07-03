import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/schema.dart';

void main() {
  setUpAll(() {
    registerAllFrRoutes();
  });

  group('frRouter migration smoke', () {
    test('fr://lab resolves to LabIndexHandler', () async {
      final match = await frRouter.resolve('fr://lab');
      expect(match, isNotNull);
      expect(match!.host, 'lab');
      expect(match.path, '');
      expect(frRouter.findHandler('lab'), isA<FrRouteHandler>());
    });

    test('fr://lab/demo/clock resolves to LabDemoHandler', () async {
      final match = await frRouter.resolve('fr://lab/demo/clock');
      expect(match, isNotNull);
      expect(match!.host, 'lab');
      expect(match.path, 'demo/clock');
      expect(frRouter.findHandler('lab'), isA<FrRouteHandler>());
    });

    test('fr://lab/core/profile resolves to LabCoreHandler', () async {
      final match = await frRouter.resolve('fr://lab/core/profile');
      expect(match, isNotNull);
      expect(match!.host, 'lab');
      expect(match.path, 'core/profile');
      expect(frRouter.findHandler('lab'), isA<FrRouteHandler>());
    });

    test('fr://notion/image-host?autocapture=true resolves with query', () async {
      final match = await frRouter.resolve('fr://notion/image-host?autocapture=true');
      expect(match, isNotNull);
      expect(match!.host, 'notion');
      expect(match.path, 'image-host');
      expect(match.queryBool('autocapture'), isTrue);
    });

    test('fr://timetable resolves to TimetableHandler', () async {
      final match = await frRouter.resolve('fr://timetable');
      expect(match, isNotNull);
      expect(match!.host, 'timetable');
    });

    test('http://lab returns null (wrong scheme)', () async {
      final match = await frRouter.resolve('http://lab');
      expect(match, isNull);
    });

    test('fr://unknown returns null (unknown host)', () async {
      final match = await frRouter.resolve('fr://unknown');
      expect(match, isNull);
    });
  });
}