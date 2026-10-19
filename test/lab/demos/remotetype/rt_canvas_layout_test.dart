// test/lab/demos/remotetype/rt_canvas_layout_test.dart
//
// 横屏画布布局逻辑单测：
//   - rtFirstFreeCanvasSlot 按钮自动找位（确定性 / 间距避让 / 全满兜底）
//   - RtCanvasAnchor（显隐 + 中心 + 宽高）JSON 往返 / 越界钳制 / 旧形状兼容
//   - RtCanvasButtonPos（中心 + 倍率 + 显隐）往返 / 旧形状（只有 x/y）兼容
//   - RtCanvasLayout 整表往返 / 坏条目只丢自己 / 坏 JSON 整表兜底
//
// 画布布局是「用户亲手拖出来的编排」，持久化契约破坏一次就丢布局——
// 改序列化形状或找位规则前先过这组用例。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('RtCanvasLayout 整表', () {
    test('round-trip：模块 + 按钮一起存取', () {
      const layout = RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(visible: false, x: 0.27, y: 0.55, w: 0.5, h: 0.7),
          'input': RtCanvasAnchor(visible: true, x: 0.73, y: 0.16),
        },
        buttons: {'default_0': RtCanvasButtonPos(x: 0.6, y: 0.34, s: 1.2)},
      );
      final restored = RtCanvasLayout.fromJson(
        layout.toJson().cast<String, dynamic>(),
      );
      expect(restored.modules['touchpad']!.visible, isFalse);
      expect(restored.modules['touchpad']!.w, 0.5);
      expect(restored.modules['input']!.w, isNull);
      expect(restored.buttons['default_0']!.s, 1.2);
    });

    test('坏条目只丢自己，好条目保留', () {
      final layout = RtCanvasLayout.fromJson({
        'modules': {
          'touchpad': {'v': true, 'x': 0.1, 'y': 0.2},
          'broken': 'not-a-map',
        },
        'buttons': {
          'a': {'x': 0.3, 'y': 0.4},
          'b': {'x': 'nan'},
          'c': [1, 2],
        },
      });
      expect(layout.modules.keys, {'touchpad'});
      expect(layout.buttons.keys, {'a'});
      expect(layout.buttons['a']!.s, 1.0);
    });

    test('withModule / withButton 不可变更新（原布局不被改写）', () {
      const base = RtCanvasLayout(
        modules: {'touchpad': RtCanvasAnchor(visible: true, x: 0.1, y: 0.1)},
      );
      final moved = base.withModule(
        'touchpad',
        const RtCanvasAnchor(visible: false, x: 0.2, y: 0.2),
      );
      final buttoned =
          base.withButton('b1', const RtCanvasButtonPos(x: 0.5, y: 0.5));
      expect(base.modules['touchpad']!.visible, isTrue);
      expect(base.buttons, isEmpty);
      expect(moved.modules['touchpad']!.visible, isFalse);
      expect(buttoned.buttons['b1'], isNotNull);
    });
  });

  group('RtPrefs 画布布局持久化', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trip：存什么读什么', () async {
      const layout = RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(visible: true, x: 0.27, y: 0.55),
          'input': RtCanvasAnchor(visible: false, x: 0.73, y: 0.16),
        },
        buttons: {'default_1': RtCanvasButtonPos(x: 0.86, y: 0.54, s: 1.8)},
      );
      await RtPrefs.saveCanvasLayout(layout);
      final loaded = await RtPrefs.loadCanvasLayout();
      expect(loaded.modules['touchpad']!.visible, isTrue);
      expect(loaded.modules['input']!.visible, isFalse);
      expect(loaded.buttons['default_1']!.s, 1.8);
    });

    test('坏 JSON 整表兜底为空（画布回内置默认），不抛错', () async {
      SharedPreferences.setMockInitialValues({
        'rt_canvas_layout_v1': 'not-json{',
      });
      final loaded = await RtPrefs.loadCanvasLayout();
      expect(loaded.modules, isEmpty);
      expect(loaded.buttons, isEmpty);
    });

    test('无数据返回空布局（首跑语义）', () async {
      final loaded = await RtPrefs.loadCanvasLayout();
      expect(loaded.modules, isEmpty);
      expect(loaded.buttons, isEmpty);
    });
  });
}
