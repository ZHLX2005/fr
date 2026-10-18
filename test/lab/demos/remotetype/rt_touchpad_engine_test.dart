// test/lab/demos/remotetype/rt_touchpad_engine_test.dart
//
// RtTouchpadEngine 纯逻辑单测：手势状态机的全部时序路径都只依赖事件自带
// 时间戳——不需要 fakeAsync，直接按毫秒喂事件即可精确复现。
//
// 覆盖：点按/移动/拖拽/右键/滚轮方向/惯性/第三指忽略/异常收尾（cancel、
// 拖拽中第二指落下）。

import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_touchpad_engine.dart';

void main() {
  // 收集器：把引擎回调攒进列表，便于断言顺序与内容。
  late RtTouchpadEngine engine;
  late List<({double dx, double dy})> moves;
  late List<RtPadAction> actions;
  late List<({int dx, int dy})> scrolls;
  late List<bool> inertiaFlips;

  RtTouchpadEngine build({double sensitivity = 1.0}) {
    return RtTouchpadEngine(
      onMove: (dx, dy) => moves.add((dx: dx, dy: dy)),
      onAction: actions.add,
      onScroll: (dx, dy) => scrolls.add((dx: dx, dy: dy)),
      onInertia: inertiaFlips.add,
      sensitivity: sensitivity,
    );
  }

  setUp(() {
    moves = [];
    actions = [];
    scrolls = [];
    inertiaFlips = [];
    engine = build();
  });

  group('加速度曲线', () {
    test('慢速压到下限，快速放到上限，中段单调不减', () {
      expect(rtPadAccelFactor(0.0), 0.5);
      expect(rtPadAccelFactor(0.05), 0.5);
      expect(rtPadAccelFactor(3.0), 3.0);
      expect(rtPadAccelFactor(10.0), 3.0);
      var prev = 0.0;
      for (var s = 0.0; s <= 3.0; s += 0.05) {
        final f = rtPadAccelFactor(s);
        expect(f, greaterThanOrEqualTo(prev));
        prev = f;
      }
    });
  });

  group('单指', () {
    test('圈内快速抬手 = 左键', () {
      engine.down(1, 100, 100, 0);
      engine.move(1, 104, 102, 40); // 位移 < kRtPadTapSlop
      engine.up(1, 104, 102, 80);
      expect(actions, [RtPadAction.leftClick]);
      expect(moves, isEmpty);
    });

    test('超时抬手（移动前）不算点按——避免长按误触点击', () {
      engine.down(1, 100, 100, 0);
      engine.up(1, 100, 100, 500);
      expect(actions, isEmpty);
    });

    test('超 slop 移动 → 指针位移，抬手不再补点按', () {
      engine.down(1, 100, 100, 0);
      engine.move(1, 130, 100, 50);
      engine.move(1, 160, 100, 100);
      engine.up(1, 160, 100, 130);
      expect(moves, isNotEmpty);
      // 合成位移方向应为 +x
      final totalDx = moves.fold(0.0, (s, m) => s + m.dx);
      expect(totalDx, greaterThan(0));
      expect(actions, isEmpty);
    });

    test('灵敏度乘子在输出上生效（2x 输入同轨迹 → 位移约 2 倍）', () {
      // 同一轨迹分别喂灵敏度 1.0 与 2.0 的两台引擎
      RtTouchpadEngine feed(RtTouchpadEngine e) {
        e.down(1, 0, 0, 0);
        e.move(1, 60, 0, 100);
        e.move(1, 120, 0, 140);
        e.up(1, 120, 0, 150);
        return e;
      }

      final slowMoves = <double>[];
      final fastMoves = <double>[];
      final base = RtTouchpadEngine(
        onMove: (dx, dy) => slowMoves.add(dx),
        onAction: actions.add,
        onScroll: (dx, dy) => scrolls.add((dx: dx, dy: dy)),
        sensitivity: 1.0,
      );
      final boost = RtTouchpadEngine(
        onMove: (dx, dy) => fastMoves.add(dx),
        onAction: actions.add,
        onScroll: (dx, dy) => scrolls.add((dx: dx, dy: dy)),
        sensitivity: 2.0,
      );
      feed(base);
      feed(boost);
      final sum1 = slowMoves.fold(0.0, (s, d) => s + d);
      final sum2 = fastMoves.fold(0.0, (s, d) => s + d);
      expect(sum1, greaterThan(0));
      expect(sum2 / sum1, closeTo(2.0, 0.01), reason: '乘子应线性缩放输出');
    });

    test('按住 ≥320ms 后移动 → 拖拽三段：press → move → release', () {
      engine.down(1, 100, 100, 0);
      engine.move(1, 140, 100, 400); // 位移超 slop 且已按住 400ms
      engine.move(1, 180, 100, 450);
      engine.up(1, 180, 100, 500);
      expect(actions, [
        RtPadAction.leftPress,
        RtPadAction.leftRelease,
      ]);
      expect(moves, isNotEmpty);
    });

    test('按住未移动直接抬手不触发拖拽', () {
      engine.down(1, 100, 100, 0);
      engine.up(1, 100, 100, 600);
      expect(actions, isEmpty);
    });
  });

  group('双指', () {
    test('双指快速抬手 = 右键（第一根抬起即判定，第二根被吞）', () {
      engine.down(1, 100, 100, 0);
      engine.down(2, 130, 100, 10);
      engine.up(1, 100, 100, 80);
      expect(actions, [RtPadAction.rightClick]);
      engine.up(2, 130, 100, 90);
      expect(actions, [RtPadAction.rightClick]);
    });

    test('双指下滑 → 滚轮向上（内容跟手：dy 全为负）', () {
      engine.down(1, 100, 100, 0);
      engine.down(2, 140, 100, 10);
      // 质心每次下移 24px：累计超过 kRtPadScrollPxPerTick 后产出整格
      engine.move(1, 100, 124, 60);
      engine.move(2, 140, 124, 60);
      engine.move(1, 100, 148, 110);
      engine.move(2, 140, 148, 110);
      engine.move(1, 100, 172, 160);
      engine.move(2, 140, 172, 160);
      expect(scrolls, isNotEmpty);
      expect(scrolls.every((s) => s.dy < 0), isTrue,
          reason: '指头下滑=内容跟手下移=滚轮向上');
      expect(scrolls.every((s) => s.dx == 0), isTrue);
    });

    test('双指横扫 → 水平滚轮', () {
      engine.down(1, 100, 100, 0);
      engine.down(2, 100, 140, 10);
      for (var i = 1; i <= 4; i++) {
        engine.move(1, 100 + i * 20, 100, i * 50);
        engine.move(2, 100 + i * 20, 140, i * 50);
      }
      expect(scrolls.where((s) => s.dx != 0), isNotEmpty);
    });

    test('滚轮中途抬走一根 → 剩指吞掉，不再滚动也不右键', () {
      engine.down(1, 100, 100, 0);
      engine.down(2, 140, 100, 10);
      // 三对移动 ≈ 72px 质心位移 ≈ 1.5 格 → 至少产出 1 格
      engine.move(1, 100, 124, 50);
      engine.move(2, 140, 124, 50);
      engine.move(1, 100, 148, 80);
      engine.move(2, 140, 148, 80);
      engine.move(1, 100, 172, 110);
      engine.move(2, 140, 172, 110);
      expect(scrolls, isNotEmpty);
      scrolls.clear();
      engine.up(1, 100, 172, 130);
      engine.move(2, 140, 240, 150); // 剩指继续动
      engine.up(2, 140, 240, 170);
      expect(scrolls, isEmpty);
      expect(actions, isEmpty);
    });
  });

  group('惯性滚动', () {
    test('快速上滑抬手 → 惯性启动，tick 继续产出并衰减停止', () {
      engine.down(1, 100, 300, 0);
      engine.down(2, 140, 300, 10);
      // 6 帧快速上移，每帧 48px / 16ms = 3px/ms（远超 fling 阈值）
      for (var i = 1; i <= 6; i++) {
        engine.move(1, 100, 300 - i * 48, 10 + i * 16);
        engine.move(2, 140, 300 - i * 48, 10 + i * 16);
      }
      engine.up(1, 100, 12, 110);
      engine.up(2, 140, 12, 110);
      expect(inertiaFlips, [true], reason: '抬手触发惯性');
      final ticksBefore = scrolls.length;

      // 模拟 60fps tick，3 秒内应自然停止
      for (var i = 0; i < 180 && engine.phaseName == 'inertia'; i++) {
        engine.tick(16);
      }
      expect(engine.phaseName, 'idle', reason: '衰减后必须停止');
      expect(inertiaFlips, [true, false]);
      expect(scrolls.length, greaterThan(ticksBefore));
      // 惯性方向延续手势：上滑 → 滚轮向下（正）
      expect(scrolls.any((s) => s.dy > 0), isTrue);
    });

    test('慢速滚动抬手不触发惯性', () {
      engine.down(1, 100, 300, 0);
      engine.down(2, 140, 300, 10);
      for (var i = 1; i <= 3; i++) {
        engine.move(1, 100, 300 + i * 10, i * 200); // 10px/200ms = 0.05px/ms
        engine.move(2, 140, 300 + i * 10, i * 200);
      }
      engine.up(1, 100, 330, 620);
      engine.up(2, 140, 330, 620);
      expect(inertiaFlips, isEmpty);
      expect(engine.phaseName, 'idle');
    });
  });

  group('三指', () {
    test('第三指落下直接忽略：不触发任何动作，双指手势照常', () {
      // 手机系统手势（截屏/应用切换）普遍占用三指——误触代价高，整段砍掉
      engine.down(1, 100, 100, 0);
      engine.down(2, 140, 100, 10);
      engine.down(3, 120, 140, 20); // 未登记
      expect(actions, isEmpty);
      // 已登记的两指继续滚轮
      engine.move(1, 100, 124, 50);
      engine.move(2, 140, 124, 50);
      engine.move(1, 100, 148, 80);
      engine.move(2, 140, 148, 80);
      engine.move(1, 100, 172, 110);
      engine.move(2, 140, 172, 110);
      expect(scrolls, isNotEmpty, reason: '第三指落下不影响双指滚轮');
      // 未登记指的 move/up 全部无效
      engine.move(3, 200, 200, 130);
      engine.up(3, 200, 200, 140);
      expect(actions, isEmpty);
      expect(moves, isEmpty);
      engine.up(1, 100, 172, 150);
      engine.up(2, 140, 172, 160);
      // 收尾滚动速度 > fling 阈值会进惯性（预期行为）：tick 到自然停止
      for (var i = 0; i < 180 && engine.phaseName == 'inertia'; i++) {
        engine.tick(16);
      }
      expect(engine.phaseName, 'idle');
    });

    test('三指同时落下（并发帧序）也只有两指登记', () {
      engine.down(1, 100, 100, 0);
      engine.down(2, 140, 100, 1);
      engine.down(3, 120, 140, 2);
      expect(actions, isEmpty);
      engine.up(1, 100, 100, 50);
      engine.up(2, 140, 100, 60);
      engine.up(3, 120, 140, 70);
      expect(engine.phaseName, 'idle');
    });
  });

  group('异常收尾', () {
    test('拖拽中 cancelAll 补发 release（防 PC 左键卡死）', () {
      engine.down(1, 100, 100, 0);
      engine.move(1, 140, 100, 400);
      expect(actions, [RtPadAction.leftPress]);
      engine.cancelAll();
      expect(actions, [RtPadAction.leftPress, RtPadAction.leftRelease]);
      expect(engine.phaseName, 'idle');
    });

    test('拖拽中第二指落下 → 立即补 release，转入双指未定态', () {
      engine.down(1, 100, 100, 0);
      engine.move(1, 140, 100, 400);
      engine.down(2, 200, 200, 420);
      expect(actions, [
        RtPadAction.leftPress,
        RtPadAction.leftRelease,
      ]);
      expect(engine.phaseName, 'twoPending');
    });

    test('cancelAll 在空闲时静默', () {
      engine.cancelAll();
      expect(actions, isEmpty);
      expect(inertiaFlips, isEmpty);
    });
  });
}
