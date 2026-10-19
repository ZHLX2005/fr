// test/lab/demos/remotetype/rt_canvas_layout_test.dart
//
// 横屏画布布局逻辑单测：
//   - rtFirstFreeCanvasSlot 按钮自动找位（确定性 / 间距避让 / 全满兜底）
//   - RtCanvasLayout / RtCanvasAnchor JSON 往返（round-trip / 越界钳制 /
//     坏条目只丢自己 / 坏 JSON 整表兜底）
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

  group('RtCanvasLayout JSON 往返', () {
    test('round-trip：存什么读什么', () {
      const layout = RtCanvasLayout(
        modules: {
          'touchpad': RtCanvasAnchor(visible: false, x: 0.27, y: 0.55),
          'input': RtCanvasAnchor(visible: true, x: 0.73, y: 0.16),
        },
        buttons: {'default_0': Offset(0.6, 0.34)},
      );
      final restored = RtCanvasLayout.fromJson(
        (layout.toJson()).cast<String, dynamic>(),
      );
      expect(restored.modules['touchpad']!.visible, isFalse);
      expect(restored.modules['touchpad']!.x, 0.27);
      expect(restored.modules['input']!.visible, isTrue);
      expect(restored.buttons['default_0'], const Offset(0.6, 0.34));
    });

    test('锚点越界钳回 0..1（拖动越界的旧数据自愈）', () {
      final anchor = RtCanvasAnchor.fromJson(
        {'v': true, 'x': 1.3, 'y': -0.4}.cast<String, dynamic>(),
      );
      expect(anchor.x, 1.0);
      expect(anchor.y, 0.0);
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
      expect(layout.buttons['a'], const Offset(0.3, 0.4));
    });

    test('withModule / withButton 不可变更新（原布局不被改写）', () {
      const base = RtCanvasLayout(
        modules: {'touchpad': RtCanvasAnchor(visible: true, x: 0.1, y: 0.1)},
      );
      final moved = base.withModule(
        'touchpad',
        const RtCanvasAnchor(visible: false, x: 0.2, y: 0.2),
      );
      expect(base.modules['touchpad']!.visible, isTrue);
      expect(moved.modules['touchpad']!.visible, isFalse);
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
        buttons: {'default_1': Offset(0.86, 0.54)},
      );
      await RtPrefs.saveCanvasLayout(layout);
      final loaded = await RtPrefs.loadCanvasLayout();
      expect(loaded.modules['touchpad']!.visible, isTrue);
      expect(loaded.modules['input']!.visible, isFalse);
      expect(loaded.buttons['default_1'], const Offset(0.86, 0.54));
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
