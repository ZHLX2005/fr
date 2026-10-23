// RT 布局可插拔化的规则测试（重构后新增）：
//   · kind（canvas / writer）决定这条布局由谁渲染——写字页是「布局之一」；
//   · editable=false = 固定死的默认布局：持久化里的改动一律丢弃；
//   · 写字页只属竖屏（横屏没有写字形态）；
//   · 竖屏默认激活 = 写字，横屏默认激活 = 触控屏；
//   · 布局集的变更操作（复制 / 删除 / 重命名 / 恢复出厂）一套规则；
//   · 回车注入方式（发送 / 换行）持久化。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/remotetype/canvas/template/rt_canvas_presets.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_layout_ops.dart';
import 'package:xiaodouzi_fr/core/remotetype/data/rt_prefs.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RtLayoutKind', () {
    test('id 与读侧兜底：未知/缺省一律按画布', () {
      expect(RtLayoutKind.writer.id, 'writer');
      expect(RtLayoutKind.canvas.id, 'canvas');
      expect(RtLayoutKind.fromId('writer'), RtLayoutKind.writer);
      expect(RtLayoutKind.fromId('canvas'), RtLayoutKind.canvas);
      expect(RtLayoutKind.fromId(null), RtLayoutKind.canvas);
      expect(RtLayoutKind.fromId('nope'), RtLayoutKind.canvas);
    });
  });

  group('命名布局的 kind / editable 持久化', () {
    test('round-trip：kind 与 editable 都带回来', () {
      const src = RtCanvasNamedLayout(
        id: 'x',
        name: 'X',
        builtIn: false,
        editable: false,
        kind: RtLayoutKind.writer,
        orientation: kRtCanvasOrientPortrait,
        data: RtCanvasLayout(),
      );
      final back = RtCanvasNamedLayout.fromJson(src.toJson());
      expect(back.kind, RtLayoutKind.writer);
      expect(back.editable, isFalse);
      expect(back.orientation, kRtCanvasOrientPortrait);
    });

    test('旧数据（无 kind / 无 editable）按画布 + 可编辑读', () {
      final back = RtCanvasNamedLayout.fromJson({
        'id': 'old',
        'name': '旧布局',
        'builtIn': true,
        'data': <String, dynamic>{},
      });
      expect(back.kind, RtLayoutKind.canvas);
      expect(back.editable, isTrue);
    });
  });

  group('写字布局（固定死的默认布局）', () {
    test('出厂形态：kind=writer / editable=false / 竖屏', () {
      final writer = rtBuiltinPresetOf(kRtCanvasPresetWriter)!;
      expect(writer.kind, RtLayoutKind.writer);
      expect(writer.editable, isFalse);
      expect(writer.builtIn, isTrue);
      expect(writer.orientation, kRtCanvasOrientPortrait);
    });

    test('只属竖屏：横屏不可用（横屏只有画布）', () {
      final writer = rtBuiltinPresetOf(kRtCanvasPresetWriter)!;
      expect(
        rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, writer),
        isTrue,
      );
      expect(
        rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, writer),
        isFalse,
      );
    });

    test('固定死 = 持久化里的改动一律丢弃（ensure 强制用出厂那份）', () {
      // 用户（或旧版本）改了写字页的数据——ensure 必须还原成出厂形态。
      final tampered = RtCanvasNamedLayout(
        id: kRtCanvasPresetWriter,
        name: '被改过的写字',
        builtIn: true,
        editable: false,
        kind: RtLayoutKind.writer,
        orientation: kRtCanvasOrientPortrait,
        data: const RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(visible: true, x: 0.9, y: 0.9),
          },
        ),
      );
      final ensured = rtEnsureBuiltinPresets(
        RtCanvasLayouts(list: [tampered], activeId: kRtCanvasPresetWriter),
      );
      final writer = ensured.list.firstWhere(
        (p) => p.id == kRtCanvasPresetWriter,
      );
      expect(writer.data.modules, isEmpty);
      expect(writer.name, '写字');
      expect(writer.editable, isFalse);
    });

    test('可编辑的内置（游戏）保留用户改过的摆放', () {
      final edited = rtBuiltinPresetOf(kRtCanvasPresetGame)!.copyWith(
        data: const RtCanvasLayout(
          modules: {
            kRtCanvasModuleDpad: RtCanvasAnchor(
              visible: true,
              x: 0.11,
              y: 0.22,
            ),
          },
        ),
      );
      final ensured = rtEnsureBuiltinPresets(
        RtCanvasLayouts(list: [edited], activeId: kRtCanvasPresetGame),
      );
      final game = ensured.list.firstWhere(
        (p) => p.id == kRtCanvasPresetGame,
      );
      expect(game.data.modules[kRtCanvasModuleDpad]!.x, 0.11);
    });
  });

  group('默认入口布局', () {
    test('竖屏默认 = 写字；横屏默认 = 触控屏', () {
      const layouts = RtCanvasLayouts(list: kRtCanvasBuiltinPresets);
      expect(
        layouts.activeFor(kRtCanvasOrientPortrait)!.id,
        kRtCanvasPresetWriter,
      );
      expect(
        layouts.activeFor(kRtCanvasOrientLandscape)!.id,
        kRtCanvasPresetTouchpad,
      );
    });

    test('横屏兜底不会落到写字页（横屏无写字形态）', () {
      final only = RtCanvasLayouts(
        list: [rtBuiltinPresetOf(kRtCanvasPresetWriter)!],
      );
      expect(only.activeFor(kRtCanvasOrientLandscape), isNull);
    });
  });

  group('布局集变更操作（rt_layout_ops）', () {
    const builtins = RtCanvasLayouts(list: kRtCanvasBuiltinPresets);

    test('复制：新增一条空自定义布局（自定义可编辑）', () {
      final next = rtLayoutsCopyToCustom(
        builtins,
        kRtCanvasOrientLandscape,
      );
      final created = next.list.last;
      expect(created.id, 'custom-1');
      expect(created.builtIn, isFalse);
      expect(created.editable, isTrue);
      expect(created.data.modules, isEmpty);
    });

    test('删除：自定义可删、内置不可删；删空集合回内置全集', () {
      final withCustom = rtLayoutsCopyToCustom(
        builtins,
        kRtCanvasOrientLandscape,
      );
      final deleted = rtLayoutsDeleteCustom(withCustom, 'custom-1');
      expect(deleted.list.length, builtins.list.length);
      // 内置删除被忽略
      final keep = rtLayoutsDeleteCustom(withCustom, kRtCanvasPresetGame);
      expect(keep.list.length, withCustom.list.length);
      // 只剩一条自定义时删它 → 回内置全集（列表不能空）
      final onlyCustom = RtCanvasLayouts(
        list: [
          const RtCanvasNamedLayout(
            id: 'custom-9',
            name: '仅有',
            builtIn: false,
            data: RtCanvasLayout(),
          ),
        ],
      );
      final back = rtLayoutsDeleteCustom(onlyCustom, 'custom-9');
      expect(back.list.length, kRtCanvasBuiltinPresets.length);
    });

    test('重命名：自定义可改、内置名固定', () {
      final withCustom = rtLayoutsCopyToCustom(
        builtins,
        kRtCanvasOrientLandscape,
      );
      final renamed = rtLayoutsRename(withCustom, 'custom-1', '我的触控盘');
      expect(renamed.list.last.name, '我的触控盘');
      final builtin = rtLayoutsRename(withCustom, kRtCanvasPresetGame, '改名');
      expect(
        builtin.list.firstWhere((p) => p.id == kRtCanvasPresetGame).name,
        '方向键布局',
      );
    });

    test('组内重排：横屏组顺序变化，竖屏专属相对位置不变', () {
      final before = builtins.list
          .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p))
          .map((p) => p.id)
          .toList();
      expect(before.first, isNot(kRtCanvasPresetTouchpad));
      // 把横屏组第 0 项挪到末尾
      final next = rtLayoutsReorder(
        builtins,
        kRtCanvasOrientLandscape,
        0,
        before.length,
      );
      final after = next.list
          .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p))
          .map((p) => p.id)
          .toList();
      expect(after.last, before.first);
      expect(after.length, before.length);
      // 写字仍在竖屏组
      expect(
        next.list.any((p) => p.id == kRtCanvasPresetWriter),
        isTrue,
      );
    });

    test('恢复出厂：内置摆放重置为代码预设', () {
      final edited = rtBuiltinPresetOf(kRtCanvasPresetTouchpad)!.copyWith(
        data: const RtCanvasLayout(
          modules: {
            kRtCanvasModuleTouchpad: RtCanvasAnchor(
              visible: false,
              x: 0.9,
              y: 0.9,
            ),
          },
        ),
      );
      final next = rtLayoutsResetBuiltin(
        RtCanvasLayouts(list: [edited], activeId: kRtCanvasPresetTouchpad),
        kRtCanvasPresetTouchpad,
      );
      final pad = next.list.firstWhere(
        (p) => p.id == kRtCanvasPresetTouchpad,
      );
      expect(pad.data.modules[kRtCanvasModuleTouchpad]!.visible, isTrue);
    });
  });

  group('回车注入方式（发送 / 换行）持久化', () {
    test('缺省 = 发送；存进去再读出来', () async {
      expect(await RtPrefs.loadEnterMode(), 'enter');
      await RtPrefs.saveEnterMode('shift_enter');
      expect(await RtPrefs.loadEnterMode(), 'shift_enter');
    });

    test('坏值兜底回发送', () async {
      await RtPrefs.saveEnterMode('nonsense');
      expect(await RtPrefs.loadEnterMode(), 'enter');
    });
  });
}
