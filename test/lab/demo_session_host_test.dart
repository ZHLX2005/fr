// DemoSessionHost 守卫测试：托管 / reattach / detach / drop / 空闲回收 / 前后台广播。
// 设计全文：docs/superpowers/specs/2026-10-12-demo-scope-design.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/app_lifecycle/app_foreground.dart';
import 'package:xiaodouzi_fr/lab/demo_session_host.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';

/// scope 判据用的最小 DemoPage 桩。
class _FakeDemo extends DemoPage {
  @override
  String get title => 'scope 桩';
  @override
  String get description => '验证 scope 默认值';
  @override
  String get slug => 'fake-scope';
  @override
  Widget buildPage(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('DemoPage.scope 默认值', () {
    test('未 override 时为 page——70 个既有 demo 零迁移', () {
      expect(_FakeDemo().scope, DemoScope.page);
    });

    test('三个分组齐全', () {
      expect(DemoScope.values, containsAll(DemoScope.values));
      expect(DemoScope.values.length, 3);
    });
  });

  group('attach / reattach', () {
    test('首次 attach 创建并托管，二次 attach 复用同一对象（绝不重建）', () async {
      final host = DemoSessionHost();
      var created = 0;
      Object session() {
        created += 1;
        return Object();
      }

      Future<void> noop() async {}

      final a = host.attach('rt', session, onDispose: noop);
      final b = host.attach('rt', session, onDispose: noop);
      expect(created, 1, reason: '重进页面必须 reattach，不允许新建第二条');
      expect(identical(a, b), isTrue);
      expect(host.count, 1);
    });

    test('reattach 清除 detached 标记', () async {
      final host = DemoSessionHost();
      host.attach('rt', Object.new, onDispose: () async {});
      host.detach('rt');
      expect(host.active['rt']!.detached, isTrue);
      host.attach('rt', Object.new, onDispose: () async {});
      expect(host.active['rt']!.detached, isFalse);
    });

    test('reattach 刷新钩子——最新在场的页面说了算', () async {
      final host = DemoSessionHost();
      var oldForeground = 0;
      var newForeground = 0;
      host.attach('rt', Object.new, onDispose: () async {},
          onAppForeground: () async => oldForeground += 1);
      host.attach('rt', Object.new, onDispose: () async {},
          onAppForeground: () async => newForeground += 1);
      await host.notifyAppForeground();
      expect(oldForeground, 0, reason: '旧页面闭包应随 reattach 被丢弃');
      expect(newForeground, 1);
    });

    test('不同 slug 各自独立托管', () {
      final host = DemoSessionHost();
      host.attach('rt', Object.new, onDispose: () async {});
      host.attach('go-room', Object.new, onDispose: () async {});
      expect(host.count, 2);
    });
  });

  group('detach / drop', () {
    test('detach 只标记不销毁——onDispose 不被调用', () async {
      final host = DemoSessionHost();
      var disposed = 0;
      host.attach('rt', Object.new, onDispose: () async => disposed += 1);
      host.detach('rt');
      expect(host.active['rt']!.detached, isTrue);
      expect(disposed, 0, reason: 'detached = 会话还在后台活着');
      expect(host.count, 1);
    });

    test('detach 未知 slug 幂等（page scope 页面可防御性调用）', () {
      final host = DemoSessionHost();
      expect(() => host.detach('nope'), returnsNormally);
    });

    test('drop 调用 onDispose 并移除', () async {
      final host = DemoSessionHost();
      var disposed = 0;
      host.attach('rt', Object.new, onDispose: () async => disposed += 1);
      await host.drop('rt');
      expect(disposed, 1);
      expect(host.count, 0);
    });

    test('drop 未知 slug 幂等', () async {
      final host = DemoSessionHost();
      await expectLater(host.drop('nope'), completes);
    });
  });

  group('空闲回收 reapIdle', () {
    final t0 = DateTime(2026, 10, 12, 12);

    test('detached 未超时不回收；attached 的永不动', () async {
      final host = DemoSessionHost();
      host.attach('attached', Object.new, onDispose: () async {});
      host.attach('fresh', Object.new, onDispose: () async {});
      host.detach('fresh', now: t0);
      // 只 detach 了 1 分钟，远小于 15 分钟阈值。
      final reaped = await host.reapIdle(
        timeout: const Duration(minutes: 15),
        now: t0.add(const Duration(minutes: 1)),
      );
      expect(reaped, isEmpty);
      expect(host.count, 2);
    });

    test('detached 超时回收，返回被回收 slug 列表', () async {
      final host = DemoSessionHost();
      var disposed = 0;
      host.attach('stale', Object.new, onDispose: () async => disposed += 1);
      host.detach('stale', now: t0);
      final reaped = await host.reapIdle(
        timeout: const Duration(minutes: 15),
        now: t0.add(const Duration(minutes: 16)),
      );
      expect(reaped, ['stale']);
      expect(disposed, 1);
      expect(host.count, 0);
    });

    test('回收后可重新 attach 全新对象', () async {
      final host = DemoSessionHost();
      final first = host.attach('rt', Object.new, onDispose: () async {});
      host.detach('rt', now: t0);
      await host.reapIdle(
        timeout: const Duration(minutes: 15),
        now: t0.add(const Duration(hours: 1)),
      );
      final second = host.attach('rt', Object.new, onDispose: () async {});
      expect(identical(first, second), isFalse, reason: '回收后再进应是全新会话');
    });

    test('单个 onDispose 抛错不阻断其余回收', () async {
      final host = DemoSessionHost();
      var goodDisposed = 0;
      host.attach('bad', Object.new, onDispose: () async => throw StateError('炸'));
      host.attach('good', Object.new, onDispose: () async => goodDisposed += 1);
      host.detach('bad', now: t0);
      host.detach('good', now: t0);
      final reaped = await host.reapIdle(
        timeout: const Duration(minutes: 15),
        now: t0.add(const Duration(hours: 1)),
      );
      expect(reaped.toSet(), {'bad', 'good'});
      expect(goodDisposed, 1);
      expect(host.count, 0);
    });
  });

  group('前后台广播', () {
    test('转发给每个会话', () async {
      final host = DemoSessionHost();
      var aBg = 0, aFg = 0, bBg = 0;
      host.attach('a', Object.new, onDispose: () async {},
          onAppBackground: () async => aBg += 1,
          onAppForeground: () async => aFg += 1);
      host.attach('b', Object.new, onDispose: () async {},
          onAppBackground: () async => bBg += 1);
      await host.notifyAppBackground();
      await host.notifyAppForeground();
      expect(aBg, 1);
      expect(aFg, 1);
      expect(bBg, 1);
    });

    test('无钩子的会话静默跳过', () async {
      final host = DemoSessionHost();
      host.attach('bare', Object.new, onDispose: () async {});
      await expectLater(
        Future.wait([host.notifyAppBackground(), host.notifyAppForeground()]),
        completes,
      );
    });
  });

  group('AppForeground 联动', () {
    tearDown(AppForeground.resetForTest);

    Future<void> drain() async {
      // 翻转处理器里 unawaited 的广播是异步派发，让 microtask 跑完
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('attach 后前台翻转自动广播给会话（无需手动 notify）', () async {
      AppForeground.resetForTest();
      final host = DemoSessionHost();
      var fg = 0, bg = 0;
      host.attach(
        'rt',
        Object.new,
        onDispose: () async {},
        onAppBackground: () async => bg += 1,
        onAppForeground: () async => fg += 1,
      );
      AppForeground.setForTest(false);
      await drain();
      AppForeground.setForTest(true);
      await drain();
      expect(bg, 1);
      expect(fg, 1);
    });

    test('没 attach 过就不挂监听（AppForeground 翻转不炸）', () async {
      AppForeground.resetForTest();
      final host = DemoSessionHost(); // 从未 attach
      AppForeground.setForTest(false);
      await drain();
      expect(host.count, 0);
    });
  });

  group('get<T> / active', () {    test('未知 slug 返回 null', () {
      expect(DemoSessionHost().get<Object>('nope'), isNull);
    });

    test('命中返回托管对象；类型不匹配 assert 拦截', () {
      final host = DemoSessionHost();
      final session = Object();
      host.attach('rt', () => session, onDispose: () async {});
      expect(identical(host.get<Object>('rt'), session), isTrue);
      expect(
        () => host.get<String>('rt'),
        throwsA(isA<AssertionError>()),
        reason: '类型不符是编程错误，debug 下必须炸出来',
      );
    });

    test('active 是只读视图', () {
      final host = DemoSessionHost();
      host.attach('rt', Object.new, onDispose: () async {});
      expect(
        () => host.active.clear(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
