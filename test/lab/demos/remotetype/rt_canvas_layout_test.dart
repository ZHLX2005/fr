// test/lab/demos/remotetype/rt_canvas_layout_test.dart
//
// 横屏画布布局逻辑单测：
//   - rtFirstFreeCanvasSlot 按钮自动找位（确定性 / 间距避让 / 全满兜底）
//   - RtCanvasAnchor（显隐 + 中心 + 宽高）JSON 往返 / 越界钳制 / 旧形状兼容
//   - RtCanvasButtonPos（中心 + 倍率 + 显隐）往返 / 旧形状（只有 x/y）兼容
//   - RtCanvasNamedLayout / RtCanvasLayouts（多套 + 激活）往返 / 非法
//     activeId 兜底 / 坏条目只丢自己 / 坏 JSON 整表兜底 / nextCustomId
//   - 布局隔离：改 A 不动 B、切回 A 修改仍在 / withRenamed 只改名
//   - rtBuiltinPresetOf 出厂查找 / rtEnsureBuiltinPresets 内置补齐（迁移用户）
//   - kRtCanvasBuiltinPresets 4 套内置 id/builtIn/name 一致性
//   - RtPrefs 旧 `rt_canvas_layout_v1` → 新 `rt_canvas_layouts_v1` 迁移
//
// 持久化契约破坏一次就丢布局——改序列化形状或找位规则前先过这组用例。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_canvas_presets.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_canvas_view.dart';
import 'package:xiaodouzi_fr/lab/demos/remotetype/rt_prefs.dart';

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
        {'v': true, 'x': 1.5, 'y': -0.1, 'w': 3.0, 'h': 0.01}
            .cast<String, dynamic>(),
      );
      expect(anchor.x, 1.0);
      expect(anchor.y, 0.0);
      expect(anchor.w, 1.0);
      expect(anchor.h, 0.05);
    });
  });

  group('RtCanvasButtonPos（按钮位）', () {
    test('round-trip：中心/倍率/显隐', () {
      const pos = RtCanvasButtonPos(x: 0.6, y: 0.34, s: 1.5, v: false);
      final restored = RtCanvasButtonPos.fromJson(
        pos.toJson().cast<String, dynamic>(),
      );
      expect(restored.x, 0.6);
      expect(restored.y, 0.34);
      expect(restored.s, 1.5);
      expect(restored.v, isFalse);
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
                    visible: true, x: 0.27, y: 0.55, w: 0.5, h: 0.7),
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
      expect(restored.activeId, kRtCanvasPresetDefault);
    });

    test('withUpdatedActive / withActive 不可变更新', () {
      const base = RtCanvasLayouts(
        list: [
          RtCanvasNamedLayout(
              id: 'a',
              name: 'A',
              builtIn: true,
              data: RtCanvasLayout()),
        ],
        activeId: 'a',
      );
      final moved = base.withUpdatedActive(const RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(visible: false, x: 0.1, y: 0.1),
        },
      ));
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
              data: RtCanvasLayout()),
          RtCanvasNamedLayout(
              id: 'custom-2',
              name: '2',
              builtIn: false,
              data: RtCanvasLayout()),
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
              data: RtCanvasLayout()),
          RtCanvasNamedLayout(
              id: 'custom-5',
              name: '5',
              builtIn: false,
              data: RtCanvasLayout()),
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
          'touchpad': RtCanvasAnchor(visible: true, x: 0.2, y: 0.2, w: 0.5, h: 0.5),
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
          'touchpad': RtCanvasAnchor(visible: true, x: 0.8, y: 0.8, w: 0.6, h: 0.6),
        },
        buttons: {'k0': RtCanvasButtonPos(x: 0.3, y: 0.7, s: 1.4)},
      ),
    );

    test('改 A 后切 B：B 原样；切回 A：修改仍在（模块与按钮都隔离）', () {
      var layouts = const RtCanvasLayouts(list: [layoutA, layoutB], activeId: 'a');
      // 在 A 里大改：触摸板挪走藏起、按钮挪位放大
      layouts = layouts.withUpdatedActive(const RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(visible: false, x: 0.1, y: 0.1, w: 0.3, h: 0.3),
        },
        buttons: {'k0': RtCanvasButtonPos(x: 0.9, y: 0.9, s: 2.0)},
      ));
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
      var layouts = const RtCanvasLayouts(list: [layoutA, layoutB], activeId: 'b');
      final renamed = layouts.withRenamed('a', '我的棋局');
      expect(renamed.list.first.name, '我的棋局');
      expect(renamed.list.first.data.modules['touchpad']!.x, 0.2);
      expect(renamed.activeId, 'b');
      expect(renamed.list[1].name, 'B');
      // 未知 id：返回同一内容（不新建实例）
      expect(identical(layouts.withRenamed('zz', 'x'), layouts), isTrue);
    });
  });

  group('rtBuiltinPresetOf / rtEnsureBuiltinPresets', () {
    test('四套内置都能查到出厂条目；自定义 / 未知 id 返回 null', () {
      for (final id in [
        kRtCanvasPresetDefault,
        kRtCanvasPresetGame,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
      ]) {
        final p = rtBuiltinPresetOf(id);
        expect(p, isNotNull, reason: id);
        expect(p!.builtIn, isTrue);
      }
      expect(rtBuiltinPresetOf('custom-1'), isNull);
      expect(rtBuiltinPresetOf('nope'), isNull);
    });

    test('恢复出厂：copyWith(data: factory.data) 后与出厂数据一致，他布局不动', () {
      // 模拟用户把「默认布局」改得面目全非后恢复出厂
      final edited = RtCanvasNamedLayout(
        id: kRtCanvasPresetDefault,
        name: '默认布局',
        builtIn: true,
        data: const RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(visible: false, x: 0.9, y: 0.9, w: 0.2, h: 0.2),
          },
        ),
      );
      final factory = rtBuiltinPresetOf(kRtCanvasPresetDefault)!;
      final restored = edited.copyWith(data: factory.data);
      expect(restored.data.modules['touchpad']!.visible, isTrue);
      expect(restored.data.modules['touchpad']!.x,
          factory.data.modules['touchpad']!.x);
      // 原条目不可变更新：edited 本身不被改动
      expect(edited.data.modules['touchpad']!.visible, isFalse);
    });

    test('rtEnsureBuiltinPresets：迁移单条导入布局 → 补 4 内置在前、自定义在后', () {
      const imported = RtCanvasNamedLayout(
        id: 'imported',
        name: '导入布局',
        builtIn: false,
        data: RtCanvasLayout(),
      );
      const layouts = RtCanvasLayouts(list: [imported], activeId: 'imported');
      final ensured = rtEnsureBuiltinPresets(layouts);
      expect(ensured.list.length, 5);
      expect(
        ensured.list.take(4).map((p) => p.id),
        [
          kRtCanvasPresetDefault,
          kRtCanvasPresetGame,
          kRtCanvasPresetKeyboard,
          kRtCanvasPresetTouchpad,
        ],
      );
      expect(ensured.list.last.id, 'imported');
      expect(ensured.activeId, 'imported');
    });

    test('rtEnsureBuiltinPresets：已齐全同序 → 原样返回（不产生新实例）', () {
      const layouts = RtCanvasLayouts(
        list: [...kRtCanvasBuiltinPresets],
        activeId: kRtCanvasPresetGame,
      );
      expect(identical(rtEnsureBuiltinPresets(layouts), layouts), isTrue);
    });

    test('rtEnsureBuiltinPresets：activeId 不在表内 → 兜底默认', () {
      const imported = RtCanvasNamedLayout(
        id: 'imported',
        name: '导入布局',
        builtIn: false,
        data: RtCanvasLayout(),
      );
      // 手工构造 activeId 悬空的坏表（fromJson 会兜底，直接构造绕过）
      const layouts = RtCanvasLayouts(list: [imported], activeId: 'ghost');
      final ensured = rtEnsureBuiltinPresets(layouts);
      expect(ensured.activeId, kRtCanvasPresetDefault);
    });
  });

  group('kRtCanvasBuiltinPresets 4 套内置', () {
    test('id / builtIn / 名称稳定', () {
      expect(kRtCanvasBuiltinPresets.length, 4);
      expect(
        kRtCanvasBuiltinPresets.map((p) => p.id),
        [
          kRtCanvasPresetDefault,
          kRtCanvasPresetGame,
          kRtCanvasPresetKeyboard,
          kRtCanvasPresetTouchpad,
        ],
      );
      expect(kRtCanvasBuiltinPresets.every((p) => p.builtIn), isTrue);
      expect(
        kRtCanvasBuiltinPresets.map((p) => p.name),
        ['默认布局', '游戏布局', '键盘布局', '触控屏布局'],
      );
    });

    test('每套都覆盖触摸板和输入框（active 渲染兜底）', () {
      for (final p in kRtCanvasBuiltinPresets) {
        expect(p.data.modules.containsKey(kRtCanvasModuleTouchpad), isTrue,
            reason: '${p.id} 缺 touchpad');
        expect(p.data.modules.containsKey(kRtCanvasModuleInput), isTrue,
            reason: '${p.id} 缺 input');
      }
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
              buttons: {
                'd1': RtCanvasButtonPos(x: 0.86, y: 0.54, s: 1.8),
              },
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
