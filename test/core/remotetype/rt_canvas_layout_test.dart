// test/core/remotetype/rt_canvas_layout_test.dart
//
// 横竖屏画布布局逻辑单测：
//   - rtFirstFreeCanvasSlot 按钮自动找位（确定性 / 间距避让 / 全满兜底）
//   - RtCanvasAnchor（显隐 + 中心 + 宽高）JSON 往返 / 越界钳制 / 旧形状兼容
//   - RtCanvasButtonPos（中心 + 倍率 + 显隐）往返 / 旧形状（只有 x/y）兼容
//   - RtCanvasNamedLayout / RtCanvasLayouts（多套 + 分朝向激活）往返 / 非法
//     activeId 兜底 / 坏条目只丢自己 / 坏 JSON 整表兜底 / nextCustomId
//   - 布局隔离：改 A 不动 B、切回 A 修改仍在 / withRenamed 只改名 /
//     横竖屏激活互不串台（withActiveFor 跨侧无效）
//   - rtBuiltinPresetOf 出厂查找 / rtEnsureBuiltinPresets 内置补齐（迁移用户）
//   - kRtCanvasBuiltinPresets 5 套内置（写字/方向键/轮盘/键盘/触控屏）一致性
//   - 触控屏双朝向（rtCanvasLayoutUsableIn）
//   - RtPrefs 旧 `rt_canvas_layout_v1` → 新 `rt_canvas_layouts_v1` 迁移
//
// 持久化契约破坏一次就丢布局——改序列化形状或找位规则前先过这组用例。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiaodouzi_fr/core/remotetype/canvas/template/rt_canvas_presets.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/rt_canvas_view.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonPos,
        RtCanvasButtonShape,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasBtnScaleMax,
        kRtCanvasDpadHitMax,
        kRtCanvasModuleDpad,
        kRtCanvasModuleInput,
        kRtCanvasModuleKb,
        kRtCanvasModuleTouchpad,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        kRtCanvasPresetDefault,
        kRtCanvasPresetGame,
        kRtCanvasPresetGameWheel,
        kRtCanvasPresetInputPage,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
        kRtCanvasPresetTouchpadN,
        kRtCanvasPresetWriter,
        RtPrefs,
        rtCanvasLayoutLocksLandscape,
        rtCanvasLayoutUsableIn;

void main() {
  group('rtFirstFreeCanvasSlot 按钮自动找位', () {
    test('空场落第一个候选槽，结果确定', () {
      final a = rtFirstFreeCanvasSlot(const {});
      final b = rtFirstFreeCanvasSlot(const {});
      expect(a, b);
      expect(a, kRtCanvasSlotAnchors.first);
    });

    test('已摆按钮 0.18 邻域内的槽被跳过', () {
      final first = rtFirstFreeCanvasSlot(const {});
      final second = rtFirstFreeCanvasSlot({first});
      expect((second - first).distance, greaterThanOrEqualTo(0.18));
    });

    test('槽全满落右侧中心兜底（不抛错、不在场外）', () {
      final placed = kRtCanvasSlotAnchors.toSet();
      expect(rtFirstFreeCanvasSlot(placed), const Offset(0.73, 0.55));
    });
  });

  group('RtCanvasAnchor（模块锚点）', () {
    test('round-trip：显隐/中心/宽高', () {
      const anchor = RtCanvasAnchor(
        visible: false,
        x: 0.27,
        y: 0.55,
        w: 0.6,
        h: 0.8,
      );
      final restored = RtCanvasAnchor.fromJson(
        anchor.toJson().cast<String, dynamic>(),
      );
      expect(restored.visible, isFalse);
      expect(restored.x, 0.27);
      expect(restored.y, 0.55);
      expect(restored.w, 0.6);
      expect(restored.h, 0.8);
    });

    test('旧形状（无 w/h）兼容读：宽高为 null（回模块默认）', () {
      final anchor = RtCanvasAnchor.fromJson(
        {'v': true, 'x': 0.1, 'y': 0.2}.cast<String, dynamic>(),
      );
      expect(anchor.w, isNull);
      expect(anchor.h, isNull);
    });

    test('宽高越界钳回 0.05..1.0，坐标钳回 0..1', () {
      final anchor = RtCanvasAnchor.fromJson(
        {
          'v': true,
          'x': 1.5,
          'y': -0.1,
          'w': 3.0,
          'h': 0.01,
        }.cast<String, dynamic>(),
      );
      expect(anchor.x, 1.0);
      expect(anchor.y, 0.0);
      expect(anchor.w, 1.0);
      expect(anchor.h, 0.05);
    });

    test('方向模式 round-trip：八向落 d8 字段并读回', () {
      const anchor = RtCanvasAnchor(
        visible: true,
        x: 0.2,
        y: 0.5,
        dir8: true,
      );
      final json = anchor.toJson();
      expect(json['d8'], isTrue);
      final restored = RtCanvasAnchor.fromJson(json.cast<String, dynamic>());
      expect(restored.dir8, isTrue);
    });

    test('方向模式稀疏：四向不落字段，旧数据读入按四向兜底', () {
      const anchor = RtCanvasAnchor(visible: true, x: 0.5, y: 0.5);
      expect(anchor.toJson().containsKey('d8'), isFalse);
      final legacy = RtCanvasAnchor.fromJson(
        {'v': true, 'x': 0.1, 'y': 0.2}.cast<String, dynamic>(),
      );
      expect(legacy.dir8, isFalse);
    });

    test('判定区域 round-trip：hit 落字段并读回', () {
      const anchor = RtCanvasAnchor(visible: true, x: 0.2, y: 0.5, hit: 1.4);
      final json = anchor.toJson();
      expect(json['hit'], 1.4);
      final restored = RtCanvasAnchor.fromJson(json.cast<String, dynamic>());
      expect(restored.hit, 1.4);
    });

    test('判定区域稀疏：默认不落字段，旧数据读入按 1.0 兜底；越界钳回限位', () {
      const anchor = RtCanvasAnchor(visible: true, x: 0.5, y: 0.5);
      expect(anchor.toJson().containsKey('hit'), isFalse);
      final legacy = RtCanvasAnchor.fromJson(
        {'v': true, 'x': 0.1, 'y': 0.2}.cast<String, dynamic>(),
      );
      expect(legacy.hit, 1.0);
      final clamped = RtCanvasAnchor.fromJson(
        {'v': true, 'x': 0.1, 'y': 0.2, 'hit': 9.0}.cast<String, dynamic>(),
      );
      expect(clamped.hit, kRtCanvasDpadHitMax);
    });

    test('copyWith：改几何不丢判定倍率，改倍率不动几何', () {
      const anchor = RtCanvasAnchor(visible: true, x: 0.3, y: 0.4, hit: 1.25);
      final moved = anchor.copyWith(x: 0.8, y: 0.9);
      expect(moved.hit, 1.25, reason: '拖动模块不能把判定倍率丢掉');
      expect(moved.x, 0.8);

      final retuned = anchor.copyWith(hit: 0.8);
      expect(retuned.hit, 0.8);
      expect(retuned.x, 0.3);
    });

    test('copyWith：改几何不丢方向模式，改模式不动几何', () {
      const anchor = RtCanvasAnchor(
        visible: true,
        x: 0.3,
        y: 0.4,
        w: 0.5,
        h: 0.6,
        dir8: true,
      );
      final moved = anchor.copyWith(x: 0.8, y: 0.9);
      expect(moved.dir8, isTrue, reason: '拖动模块不能把八向模式丢掉');
      expect(moved.x, 0.8);
      expect(moved.w, 0.5);

      final four = anchor.copyWith(dir8: false);
      expect(four.dir8, isFalse);
      expect(four.x, 0.3);
      expect(four.h, 0.6);
    });
  });

  group('RtCanvasButtonPos（按钮位）', () {
    test('round-trip：中心/倍率/显隐/圆形形状', () {
      const pos = RtCanvasButtonPos(
        x: 0.6,
        y: 0.34,
        s: 1.5,
        v: false,
        shape: RtCanvasButtonShape.circle,
      );
      final restored = RtCanvasButtonPos.fromJson(
        pos.toJson().cast<String, dynamic>(),
      );
      expect(restored.x, 0.6);
      expect(restored.y, 0.34);
      expect(restored.s, 1.5);
      expect(restored.v, isFalse);
      expect(restored.shape, RtCanvasButtonShape.circle);
      // 胶囊（默认）不落 shape 字段，读回仍是胶囊
      const pill = RtCanvasButtonPos(x: 0.1, y: 0.2);
      expect(
        RtCanvasButtonPos.fromJson(pill.toJson().cast<String, dynamic>()).shape,
        RtCanvasButtonShape.pill,
      );
    });

    test('旧形状（只有 x/y）兼容读：倍率 1.0、可见', () {
      final pos = RtCanvasButtonPos.fromJson(
        {'x': 0.3, 'y': 0.4}.cast<String, dynamic>(),
      );
      expect(pos.s, 1.0);
      expect(pos.v, isTrue);
    });

    test('倍率越界钳回限位，copyWith 不可变更新', () {
      final pos = RtCanvasButtonPos.fromJson(
        {'x': 0.5, 'y': 0.5, 's': 9.0, 'v': false}.cast<String, dynamic>(),
      );
      expect(pos.s, kRtCanvasBtnScaleMax);

      final base = const RtCanvasButtonPos(x: 0.1, y: 0.1);
      final moved = base.copyWith(x: 0.2, v: false);
      expect(base.x, 0.1);
      expect(base.v, isTrue);
      expect(moved.x, 0.2);
      expect(moved.s, 1.0);
      expect(moved.v, isFalse);
    });
  });

  group('RtCanvasLayouts（多套布局）', () {
    test('round-trip：模块 + 按钮一起存取', () {
      const layouts = RtCanvasLayouts(
        list: [
          RtCanvasNamedLayout(
            id: 'default',
            name: '默认',
            builtIn: true,
            data: RtCanvasLayout(
              modules: {
                'touchpad': RtCanvasAnchor(
                  visible: true,
                  x: 0.27,
                  y: 0.55,
                  w: 0.5,
                  h: 0.7,
                ),
              },
              buttons: {
                'default_0': RtCanvasButtonPos(x: 0.6, y: 0.34, s: 1.2),
              },
            ),
          ),
        ],
        activeId: 'default',
      );
      final restored = RtCanvasLayouts.fromJson(
        layouts.toJson().cast<String, dynamic>(),
      );
      expect(restored.activeId, 'default');
      expect(restored.active?.data.modules['touchpad']?.w, 0.5);
      expect(restored.active?.data.buttons['default_0']?.s, 1.2);
    });

    test('坏条目只丢自己：activeId 不存在时回默认', () {
      final restored = RtCanvasLayouts.fromJson({
        'list': [
          {'id': 'a', 'name': 'A', 'builtIn': true, 'data': {}},
          {'id': 'broken'},
        ],
        'activeId': 'nonexistent',
      });
      expect(restored.list.map((p) => p.id), ['a']);
      expect(restored.activeId, kRtCanvasPresetTouchpad);
    });

    test('withUpdatedActive / withActive 不可变更新', () {
      const base = RtCanvasLayouts(
        list: [
          RtCanvasNamedLayout(
            id: 'a',
            name: 'A',
            builtIn: true,
            data: RtCanvasLayout(),
          ),
        ],
        activeId: 'a',
      );
      final moved = base.withUpdatedActive(
        const RtCanvasLayout(
          modules: {'touchpad': RtCanvasAnchor(visible: false, x: 0.1, y: 0.1)},
        ),
      );
      final switched = base.withActive('a');
      expect(base.activeData.modules, isEmpty);
      expect(moved.activeData.modules['touchpad']!.visible, isFalse);
      expect(moved.activeId, 'a');
      expect(switched.activeId, 'a');
    });

    test('nextCustomId 顺延：取最小未占', () {
      const base = RtCanvasLayouts(
        list: [
          RtCanvasNamedLayout(
            id: 'custom-1',
            name: '1',
            builtIn: false,
            data: RtCanvasLayout(),
          ),
          RtCanvasNamedLayout(
            id: 'custom-2',
            name: '2',
            builtIn: false,
            data: RtCanvasLayout(),
          ),
        ],
        activeId: 'custom-1',
      );
      expect(base.nextCustomId(), 'custom-3');
    });

    test('nextCustomId 跳过空 id（取最小可用）', () {
      const base = RtCanvasLayouts(
        list: [
          RtCanvasNamedLayout(
            id: 'custom-3',
            name: '3',
            builtIn: false,
            data: RtCanvasLayout(),
          ),
          RtCanvasNamedLayout(
            id: 'custom-5',
            name: '5',
            builtIn: false,
            data: RtCanvasLayout(),
          ),
        ],
        activeId: 'custom-3',
      );
      expect(base.nextCustomId(), 'custom-1');
    });
  });

  group('布局隔离（每套配置互不串）', () {
    const layoutA = RtCanvasNamedLayout(
      id: 'a',
      name: 'A',
      builtIn: true,
      data: RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(
            visible: true,
            x: 0.2,
            y: 0.2,
            w: 0.5,
            h: 0.5,
          ),
        },
        buttons: {'k0': RtCanvasButtonPos(x: 0.7, y: 0.3, s: 1.0)},
      ),
    );
    const layoutB = RtCanvasNamedLayout(
      id: 'b',
      name: 'B',
      builtIn: true,
      data: RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(
            visible: true,
            x: 0.8,
            y: 0.8,
            w: 0.6,
            h: 0.6,
          ),
        },
        buttons: {'k0': RtCanvasButtonPos(x: 0.3, y: 0.7, s: 1.4)},
      ),
    );

    test('改 A 后切 B：B 原样；切回 A：修改仍在（模块与按钮都隔离）', () {
      var layouts = const RtCanvasLayouts(
        list: [layoutA, layoutB],
        activeId: 'a',
      );
      // 在 A 里大改：触摸板挪走藏起、按钮挪位放大
      layouts = layouts.withUpdatedActive(
        const RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: false,
              x: 0.1,
              y: 0.1,
              w: 0.3,
              h: 0.3,
            ),
          },
          buttons: {'k0': RtCanvasButtonPos(x: 0.9, y: 0.9, s: 2.0)},
        ),
      );
      layouts = layouts.withActive('b');
      expect(layouts.activeData.modules['touchpad']!.x, 0.8);
      expect(layouts.activeData.modules['touchpad']!.visible, isTrue);
      expect(layouts.activeData.buttons['k0']!.x, 0.3);
      expect(layouts.activeData.buttons['k0']!.s, 1.4);
      layouts = layouts.withActive('a');
      expect(layouts.activeData.modules['touchpad']!.visible, isFalse);
      expect(layouts.activeData.modules['touchpad']!.x, 0.1);
      expect(layouts.activeData.buttons['k0']!.x, 0.9);
      expect(layouts.activeData.buttons['k0']!.s, 2.0);
    });

    test('withRenamed 只改名字，数据与激活不变；id 不存在原样返回', () {
      var layouts = const RtCanvasLayouts(
        list: [layoutA, layoutB],
        activeId: 'b',
      );
      final renamed = layouts.withRenamed('a', '我的棋局');
      expect(renamed.list.first.name, '我的棋局');
      expect(renamed.list.first.data.modules['touchpad']!.x, 0.2);
      expect(renamed.activeId, 'b');
      expect(renamed.list[1].name, 'B');
      // 未知 id：返回同一内容（不新建实例）
      expect(identical(layouts.withRenamed('zz', 'x'), layouts), isTrue);
    });
  });

  group('朝向隔离（横竖屏激活互不串台）', () {
    // 锁横屏（含可见 dpad）= 竖屏不可用；空布局 / 纯触摸板 = 双朝向。
    const landLockedA = RtCanvasNamedLayout(
      id: 'land-a',
      name: '横锁A',
      builtIn: true,
      data: RtCanvasLayout(
        modules: {
          kRtCanvasModuleDpad: RtCanvasAnchor(visible: true, x: 0.2, y: 0.5),
        },
      ),
    );
    const landLockedB = RtCanvasNamedLayout(
      id: 'land-b',
      name: '横锁B',
      builtIn: true,
      data: RtCanvasLayout(
        modules: {
          kRtCanvasModuleKb: RtCanvasAnchor(visible: true, x: 0.5, y: 0.5),
        },
      ),
    );
    const landDual = RtCanvasNamedLayout(
      id: 'land-dual',
      name: '触控样',
      builtIn: true,
      data: RtCanvasLayout(
        modules: {
          kRtCanvasModuleTouchpad: RtCanvasAnchor(
            visible: true,
            x: 0.5,
            y: 0.5,
            w: 1,
            h: 1,
          ),
        },
      ),
    );
    const portA = RtCanvasNamedLayout(
      id: 'port-a',
      name: '竖A',
      builtIn: true,
      orientation: kRtCanvasOrientPortrait,
      data: RtCanvasLayout(),
    );
    const portB = RtCanvasNamedLayout(
      id: 'port-b',
      name: '竖B',
      builtIn: true,
      orientation: kRtCanvasOrientPortrait,
      data: RtCanvasLayout(),
    );
    const base = RtCanvasLayouts(
      list: [landLockedA, landLockedB, landDual, portA, portB],
      activeId: 'land-a',
      activeIdPortrait: 'port-a',
    );

    test('activeFor 各取各侧；竖屏空激活兜底竖屏第一条 / 双朝向', () {
      final layouts = base;
      expect(layouts.activeFor(kRtCanvasOrientLandscape)!.id, 'land-a');
      expect(layouts.activeFor(kRtCanvasOrientPortrait)!.id, 'port-a');
      // 仅锁横屏布局 → 竖屏无可用
      const onlyLocked = RtCanvasLayouts(
        list: [landLockedA, landLockedB],
        activeId: 'land-a',
      );
      expect(onlyLocked.activeFor(kRtCanvasOrientPortrait), isNull);
      // 仅双朝向横屏 → 竖屏兜底到它
      const onlyDual = RtCanvasLayouts(list: [landDual], activeId: 'land-dual');
      expect(onlyDual.activeFor(kRtCanvasOrientPortrait)!.id, 'land-dual');
      // 竖屏激活指向锁横屏 id（脏）→ 兜底第一条竖屏
      final dirty = RtCanvasLayouts(
        list: [landLockedA, portA, portB],
        activeId: 'land-a',
        activeIdPortrait: 'land-a',
      );
      expect(dirty.activeFor(kRtCanvasOrientPortrait)!.id, 'port-a');
    });

    test('withActiveFor 只动对应侧；锁横屏 id 不能作竖屏激活', () {
      var layouts = base;
      layouts = layouts.withActiveFor(kRtCanvasOrientPortrait, 'port-b');
      expect(layouts.activeIdPortrait, 'port-b');
      expect(layouts.activeId, 'land-a');
      // 锁横屏 id → 竖屏不可用，原样返回
      final crossed = layouts.withActiveFor(kRtCanvasOrientPortrait, 'land-a');
      expect(identical(crossed, layouts), isTrue);
      // 双朝向触控可作竖屏激活
      layouts = layouts.withActiveFor(kRtCanvasOrientPortrait, 'land-dual');
      expect(layouts.activeIdPortrait, 'land-dual');
      layouts = layouts.withActiveFor(kRtCanvasOrientLandscape, 'land-b');
      expect(layouts.activeId, 'land-b');
      expect(layouts.activeIdPortrait, 'land-dual');
    });

    test('withUpdatedActiveFor 只更新对应侧激活布局的数据', () {
      var layouts = base.withUpdatedActiveFor(
        kRtCanvasOrientPortrait,
        const RtCanvasLayout(hideShortcuts: true),
      );
      expect(
        layouts.activeFor(kRtCanvasOrientPortrait)!.data.hideShortcuts,
        isTrue,
      );
      expect(
        layouts.activeFor(kRtCanvasOrientLandscape)!.data.hideShortcuts,
        isFalse,
      );
    });

    test('round-trip：朝向与竖屏激活一起存取；旧数据（无 or/activeN）缺省横屏', () {
      final restored = RtCanvasLayouts.fromJson(
        base.toJson().cast<String, dynamic>(),
      );
      expect(restored.activeId, 'land-a');
      expect(restored.activeIdPortrait, 'port-a');
      expect(restored.activeFor(kRtCanvasOrientPortrait)!.id, 'port-a');
      // 旧形状：条目无 or → 横屏；无 activeN → 兜底竖屏第一条
      final legacy = RtCanvasLayouts.fromJson({
        'list': [
          {'id': 'a', 'name': 'A', 'builtIn': true, 'data': {}},
          {
            'id': 'p',
            'name': 'P',
            'builtIn': true,
            'or': 'portrait',
            'data': {},
          },
        ],
        'activeId': 'a',
      });
      expect(legacy.list.first.orientation, kRtCanvasOrientLandscape);
      expect(legacy.activeIdPortrait, 'p');
    });
  });

  group('rtBuiltinPresetOf / rtEnsureBuiltinPresets', () {
    test('五套内置都能查到；退役 / 自定义 / 未知 id 返回 null', () {
      for (final id in [
        kRtCanvasPresetWriter,
        kRtCanvasPresetGame,
        kRtCanvasPresetGameWheel,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
      ]) {
        final p = rtBuiltinPresetOf(id);
        expect(p, isNotNull, reason: id);
        expect(p!.builtIn, isTrue);
      }
      expect(rtBuiltinPresetOf(kRtCanvasPresetDefault), isNull);
      expect(rtBuiltinPresetOf(kRtCanvasPresetTouchpadN), isNull);
      // 输入页已退役（由固定死的「写字」接管竖屏入口）。
      expect(rtBuiltinPresetOf(kRtCanvasPresetInputPage), isNull);
      expect(rtBuiltinPresetOf('custom-1'), isNull);
      expect(rtBuiltinPresetOf('nope'), isNull);
    });

    test('恢复出厂：copyWith(data: factory.data) 后与出厂数据一致', () {
      final edited = RtCanvasNamedLayout(
        id: kRtCanvasPresetTouchpad,
        name: '触控屏布局',
        builtIn: true,
        data: const RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: false,
              x: 0.9,
              y: 0.9,
              w: 0.2,
              h: 0.2,
            ),
          },
        ),
      );
      final factory = rtBuiltinPresetOf(kRtCanvasPresetTouchpad)!;
      final restored = edited.copyWith(data: factory.data);
      expect(restored.data.modules['touchpad']!.visible, isTrue);
      expect(restored.data.modules['touchpad']!.w, 1.0);
      expect(edited.data.modules['touchpad']!.visible, isFalse);
    });

    test('rtEnsureBuiltinPresets：迁移单条导入 → 补 5 内置在前、自定义在后', () {
      const imported = RtCanvasNamedLayout(
        id: 'imported',
        name: '导入布局',
        builtIn: false,
        data: RtCanvasLayout(),
      );
      const layouts = RtCanvasLayouts(list: [imported], activeId: 'imported');
      final ensured = rtEnsureBuiltinPresets(layouts);
      expect(ensured.list.length, 6);
      expect(ensured.list.take(5).map((p) => p.id), [
        kRtCanvasPresetWriter,
        kRtCanvasPresetGame,
        kRtCanvasPresetGameWheel,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
      ]);
      expect(ensured.list.last.id, 'imported');
      expect(ensured.activeId, 'imported');
      // 竖屏激活兜底 = 写字（列表里第一套真竖屏内置）。
      expect(
        ensured.activeFor(kRtCanvasOrientPortrait)!.id,
        kRtCanvasPresetWriter,
      );
    });

    test('rtEnsureBuiltinPresets：剔除退役内置 default / touchpad-n / input-page', () {
      const retired = RtCanvasNamedLayout(
        id: kRtCanvasPresetDefault,
        name: '默认布局',
        builtIn: true,
        data: RtCanvasLayout(),
      );
      const retiredN = RtCanvasNamedLayout(
        id: kRtCanvasPresetTouchpadN,
        name: '触控屏 · 竖',
        builtIn: true,
        orientation: kRtCanvasOrientPortrait,
        data: RtCanvasLayout(),
      );
      const retiredPage = RtCanvasNamedLayout(
        id: kRtCanvasPresetInputPage,
        name: '输入页',
        builtIn: true,
        orientation: kRtCanvasOrientPortrait,
        data: RtCanvasLayout(),
      );
      const layouts = RtCanvasLayouts(
        list: [retired, retiredN, retiredPage],
        activeId: kRtCanvasPresetDefault,
        activeIdPortrait: kRtCanvasPresetTouchpadN,
      );
      final ensured = rtEnsureBuiltinPresets(layouts);
      expect(ensured.list.map((p) => p.id), [
        kRtCanvasPresetWriter,
        kRtCanvasPresetGame,
        kRtCanvasPresetGameWheel,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
      ]);
      expect(ensured.activeId, kRtCanvasPresetTouchpad);
      // 退役的竖屏激活清空 → 读侧兜底到写字。
      expect(ensured.activeIdPortrait, isEmpty);
      expect(
        ensured.activeFor(kRtCanvasOrientPortrait)!.id,
        kRtCanvasPresetWriter,
      );
    });

    test('rtEnsureBuiltinPresets：已齐全同序 → 原样返回（不产生新实例）', () {
      const layouts = RtCanvasLayouts(
        list: [...kRtCanvasBuiltinPresets],
        activeId: kRtCanvasPresetGame,
      );
      expect(identical(rtEnsureBuiltinPresets(layouts), layouts), isTrue);
    });

    test('rtEnsureBuiltinPresets：出厂修订落后 → 强制覆盖内置、自定义保留', () {
      final staleGame = kRtCanvasBuiltinPresets
          .firstWhere((p) => p.id == kRtCanvasPresetGame)
          .copyWith(
            data: const RtCanvasLayout(
              hideShortcuts: true,
              modules: {
                kRtCanvasModuleDpad: RtCanvasAnchor(
                  visible: true,
                  x: 0.22,
                  y: 0.52,
                  w: 0.30,
                  h: 0.78,
                ),
              },
            ),
          );
      const custom = RtCanvasNamedLayout(
        id: 'custom-1',
        name: '我的',
        builtIn: false,
        data: RtCanvasLayout(),
      );
      final layouts = RtCanvasLayouts(
        list: [
          for (final p in kRtCanvasBuiltinPresets)
            p.id == kRtCanvasPresetGame ? staleGame : p,
          custom,
        ],
        activeId: kRtCanvasPresetGame,
      );
      final ensured = rtEnsureBuiltinPresets(layouts, persistedFactoryRev: 0);
      expect(
        ensured.list
            .firstWhere((p) => p.id == kRtCanvasPresetGame)
            .data
            .modules,
        rtBuiltinPresetOf(kRtCanvasPresetGame)!.data.modules,
      );
      expect(ensured.list.any((p) => p.id == 'custom-1'), isTrue);
      final kept = rtEnsureBuiltinPresets(
        layouts,
        persistedFactoryRev: kRtCanvasBuiltinFactoryRev,
      );
      expect(
        kept.list.firstWhere((p) => p.id == kRtCanvasPresetGame).data.modules,
        staleGame.data.modules,
      );
    });

    test('rtEnsureBuiltinPresets：activeId 不在表内 → 兜底触控屏', () {
      const imported = RtCanvasNamedLayout(
        id: 'imported',
        name: '导入布局',
        builtIn: false,
        data: RtCanvasLayout(),
      );
      const layouts = RtCanvasLayouts(list: [imported], activeId: 'ghost');
      final ensured = rtEnsureBuiltinPresets(layouts);
      expect(ensured.activeId, kRtCanvasPresetTouchpad);
    });

    test('rtEnsureBuiltinPresets：竖屏激活指向锁横屏布局 → 清空（读侧兜底写字）', () {
      const imported = RtCanvasNamedLayout(
        id: 'imported',
        name: '导入布局',
        builtIn: false,
        data: RtCanvasLayout(
          modules: {
            kRtCanvasModuleKb: RtCanvasAnchor(visible: true, x: 0.5, y: 0.5),
          },
        ),
      );
      const layouts = RtCanvasLayouts(
        list: [imported],
        activeId: 'imported',
        activeIdPortrait: 'imported',
      );
      final ensured = rtEnsureBuiltinPresets(layouts);
      expect(ensured.activeIdPortrait, isEmpty);
      expect(
        ensured.activeFor(kRtCanvasOrientPortrait)!.id,
        kRtCanvasPresetWriter,
      );
    });
  });

  group('rtCanvasLayoutLocksLandscape / UsableIn', () {
    test('游戏/键盘锁横屏；写字页竖屏专属；触控屏不锁且双朝向可用', () {
      final game = rtBuiltinPresetOf(kRtCanvasPresetGame)!;
      expect(rtCanvasLayoutLocksLandscape(game.data), isTrue);
      expect(rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, game), isFalse);
      final kb = rtBuiltinPresetOf(kRtCanvasPresetKeyboard)!;
      expect(rtCanvasLayoutLocksLandscape(kb.data), isTrue);
      // 写字页：竖屏专属（kind=writer，横屏没有写字形态）。
      final writer = rtBuiltinPresetOf(kRtCanvasPresetWriter)!;
      expect(writer.orientation, kRtCanvasOrientPortrait);
      expect(
        rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, writer),
        isTrue,
      );
      expect(
        rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, writer),
        isFalse,
      );
      final pad = rtBuiltinPresetOf(kRtCanvasPresetTouchpad)!;
      expect(rtCanvasLayoutLocksLandscape(pad.data), isFalse);
      expect(rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, pad), isTrue);
      expect(rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, pad), isTrue);
      const hidden = RtCanvasLayout(
        modules: {
          kRtCanvasModuleDpad: RtCanvasAnchor(visible: false, x: 0.2, y: 0.2),
        },
      );
      expect(rtCanvasLayoutLocksLandscape(hidden), isFalse);
    });
  });

  group('kRtCanvasBuiltinPresets 5 套内置（写字/方向键/轮盘/键盘/触控屏）', () {
    test('id / builtIn / 名称 / 朝向稳定', () {
      expect(kRtCanvasBuiltinPresets.length, 5);
      expect(kRtCanvasBuiltinPresets.map((p) => p.id), [
        kRtCanvasPresetWriter,
        kRtCanvasPresetGame,
        kRtCanvasPresetGameWheel,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
      ]);
      expect(kRtCanvasBuiltinPresets.every((p) => p.builtIn), isTrue);
      expect(kRtCanvasBuiltinPresets.map((p) => p.name), [
        '写字',
        '方向键布局',
        '轮盘布局',
        '键盘布局',
        '触控屏布局',
      ]);
      expect(kRtCanvasBuiltinPresets.map((p) => p.orientation).toList(), [
        kRtCanvasOrientPortrait,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientLandscape,
      ]);
    });

    test('键盘=全键盘 hotkey（无触摸板/输入框）', () {
      final kb = kRtCanvasBuiltinPresets.firstWhere(
        (x) => x.id == kRtCanvasPresetKeyboard,
      );
      expect(kb.data.modules[kRtCanvasModuleKb]?.visible, isTrue);
      expect(kb.data.modules.containsKey(kRtCanvasModuleTouchpad), isFalse);
      expect(kb.data.modules.containsKey(kRtCanvasModuleInput), isFalse);
      expect(kb.data.hideShortcuts, isTrue);
      final kba = kb.data.modules[kRtCanvasModuleKb]!;
      expect(kba.x, 0.50);
      expect(kba.y, 0.55);
      expect(kba.w, 0.94);
      expect(kba.h, 0.82);
    });

    test('方向键=四向十字；轮盘=八向 dir8；触控屏=满屏触摸板', () {
      final game = kRtCanvasBuiltinPresets.firstWhere(
        (p) => p.id == kRtCanvasPresetGame,
      );
      expect(game.data.modules[kRtCanvasModuleDpad]?.visible, isTrue);
      expect(game.data.modules[kRtCanvasModuleDpad]?.dir8, isFalse);
      expect(game.data.modules[kRtCanvasModuleVpad]?.visible, isTrue);
      expect(game.data.hideShortcuts, isTrue);
      expect(game.data.modules.containsKey(kRtCanvasModuleTouchpad), isFalse);
      expect(game.data.modules.containsKey(kRtCanvasModuleInput), isFalse);

      final wheel = kRtCanvasBuiltinPresets.firstWhere(
        (p) => p.id == kRtCanvasPresetGameWheel,
      );
      expect(wheel.data.modules[kRtCanvasModuleDpad]?.dir8, isTrue);
      expect(wheel.data.modules[kRtCanvasModuleVpad]?.visible, isTrue);
      expect(wheel.data.hideShortcuts, isTrue);

      final pad = kRtCanvasBuiltinPresets.firstWhere(
        (p) => p.id == kRtCanvasPresetTouchpad,
      );
      expect(pad.data.modules[kRtCanvasModuleTouchpad]?.visible, isTrue);
      expect(pad.data.modules.length, 1);
      expect(pad.data.modules[kRtCanvasModuleTouchpad]!.w, 1.0);
      expect(pad.data.modules[kRtCanvasModuleTouchpad]!.h, 1.0);
      // 触控屏不靠 hideShortcuts，靠 buttons 空 + 使用态 opt-in 不渲染。
      expect(pad.data.hideShortcuts, isFalse);
      expect(pad.data.buttons, isEmpty);
    });

    test('空布局（新建自定义起点）= 无模块无按钮', () {
      const empty = RtCanvasLayout();
      expect(empty.modules, isEmpty);
      expect(empty.buttons, isEmpty);
      expect(empty.hideShortcuts, isFalse);
    });

    test('游戏布局锚点与原型 LAYOUTS.game 同源、两端互不相交', () {
      final game = kRtCanvasBuiltinPresets.firstWhere(
        (p) => p.id == kRtCanvasPresetGame,
      );
      final dpad = game.data.modules[kRtCanvasModuleDpad]!;
      final vpad = game.data.modules[kRtCanvasModuleVpad]!;
      expect(dpad.x, 0.21);
      expect(dpad.y, 0.54);
      expect(dpad.w, 0.22);
      expect(dpad.h, 0.52);
      expect(vpad.x, 0.765);
      expect(vpad.y, 0.53);
      expect(vpad.w, 0.36);
      expect(vpad.h, 0.70);
      expect(dpad.x + dpad.w! / 2, lessThan(vpad.x - vpad.w! / 2));
    });
  });

  group('RtPrefs 画布布局持久化', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trip：存什么读什么', () async {
      const layouts = RtCanvasLayouts(
        list: [
          RtCanvasNamedLayout(
            id: 'default',
            name: '默认',
            builtIn: true,
            data: RtCanvasLayout(
              modules: {
                'touchpad': RtCanvasAnchor(visible: true, x: 0.27, y: 0.55),
              },
              buttons: {'d1': RtCanvasButtonPos(x: 0.86, y: 0.54, s: 1.8)},
            ),
          ),
        ],
        activeId: 'default',
      );
      await RtPrefs.saveCanvasLayouts(layouts);
      final loaded = await RtPrefs.loadCanvasLayouts();
      expect(loaded.active?.data.modules['touchpad']?.visible, isTrue);
      expect(loaded.active?.data.buttons['d1']?.s, 1.8);
    });

    test('坏 JSON 整表兜底为空（首跑语义），不抛错', () async {
      SharedPreferences.setMockInitialValues({
        'rt_canvas_layouts_v1': 'not-json{',
      });
      final loaded = await RtPrefs.loadCanvasLayouts();
      expect(loaded.list, isEmpty);
    });

    test('无数据返回空集（首跑由画布在内存里铺内置，不写盘）', () async {
      final loaded = await RtPrefs.loadCanvasLayouts();
      expect(loaded.list, isEmpty);
    });

    test('迁移：旧 `rt_canvas_layout_v1` 自动包为「导入布局」并激活', () async {
      SharedPreferences.setMockInitialValues({
        'rt_canvas_layout_v1':
            '{"modules": {"touchpad": {"v": true, "x": 0.3, "y": 0.3}}}',
      });
      final loaded = await RtPrefs.loadCanvasLayouts();
      expect(loaded.list.length, 1);
      expect(loaded.list.first.id, 'imported');
      expect(loaded.activeId, 'imported');
      final p = await SharedPreferences.getInstance();
      expect(p.getString('rt_canvas_layout_v1'), isNotNull);
    });
  });
}
