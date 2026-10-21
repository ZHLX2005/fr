// lib/core/remotetype/canvas/template/rt_canvas_presets.dart
//
// 画布内置布局模板登记（模板本体在 template/ 下按套分文件）：
//   · 游戏   = 纯手柄（vpad_dpad + vpad_button/trigger）      → rt_canvas_template_game
//   · 键盘   = 全键盘（hotkey，Fn 行折叠）                    → rt_canvas_template_keyboard
//   · 输入页 = 竖屏默认：连接后落到的打字页本身               → rt_canvas_template_input_page
//   · 触控屏 = 满屏触摸板（双朝向可用）                       → rt_canvas_template_touchpad
// 用户可改；改后存盘。自定义无数量上限。
// 「默认布局」「触控屏 · 竖」已退役——ensure 会剔除旧内置条目。
// 本件只做登记与内置集合的守恒（ensure / 出厂修订），不含摆放数据。

import '../../data/rt_prefs.dart'
    show
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        kRtCanvasPresetTouchpad,
        rtCanvasLayoutUsableIn;
import 'rt_canvas_template_game.dart' show kRtCanvasTemplateGame;
import 'rt_canvas_template_input_page.dart' show kRtCanvasTemplateInputPage;
import 'rt_canvas_template_keyboard.dart' show kRtCanvasTemplateKeyboard;
import 'rt_canvas_template_touchpad.dart' show kRtCanvasTemplateTouchpad;

/// 内置模板列表（按 UI 展示顺序）。用户可改；改后存盘，下次启动沿用用户版。
const List<RtCanvasNamedLayout> kRtCanvasBuiltinPresets = [
  kRtCanvasTemplateGame,
  kRtCanvasTemplateKeyboard,
  kRtCanvasTemplateInputPage,
  kRtCanvasTemplateTouchpad,
];

/// 按 id 查内置预设出厂条目（「恢复默认布局」用）；自定义 / 退役 id 查不到返回 null。
RtCanvasNamedLayout? rtBuiltinPresetOf(String id) {
  for (final p in kRtCanvasBuiltinPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 出厂锚点修订号：升高时 [rtEnsureBuiltinPresets] 强制用新工厂覆盖全部内置
/// （自定义布局保留）。rev 4 = 新增竖屏内置「输入页」（连接后落到的打字页）。
const int kRtCanvasBuiltinFactoryRev = 4;

/// 保证布局集里 4 套内置总在场（缺的补出厂版），退役内置剔除；内置按列表
/// 顺序（横屏两套 → 竖屏输入页 → 双朝向触控屏）、自定义跟后；两个朝向的
/// 激活 id 都必须可用。
///
/// [persistedFactoryRev] < [kRtCanvasBuiltinFactoryRev] 时强制用当前出厂
/// 覆盖内置数据。已齐全且顺序一致、两侧激活都有效、且出厂修订已对齐时
/// 原样返回。纯函数，规则改动须同步单测（rt_canvas_layout_test.dart）。
RtCanvasLayouts rtEnsureBuiltinPresets(
  RtCanvasLayouts layouts, {
  int persistedFactoryRev = kRtCanvasBuiltinFactoryRev,
}) {
  final byId = {for (final p in layouts.list) p.id: p};
  final reapplyFactory = persistedFactoryRev < kRtCanvasBuiltinFactoryRev;
  final merged = [
    for (final b in kRtCanvasBuiltinPresets)
      reapplyFactory ? b : (byId[b.id] ?? b),
    // 只保留自定义；旧内置（default / touchpad-n）随工厂列表收缩自然剔除。
    ...layouts.list.where((p) => !p.builtIn),
  ];
  var sameShape = !reapplyFactory && merged.length == layouts.list.length;
  if (sameShape) {
    for (var i = 0; i < merged.length; i++) {
      if (merged[i].id != layouts.list[i].id) {
        sameShape = false;
        break;
      }
    }
  }
  final landscapeOk = merged.any((p) => p.id == layouts.activeId);
  // 竖屏激活：空 = 读侧兜底；非空须指向竖屏可用布局（真竖屏或双朝向触控屏）。
  final portraitOk =
      layouts.activeIdPortrait.isEmpty ||
      merged.any(
        (p) =>
            p.id == layouts.activeIdPortrait &&
            rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p),
      );
  if (sameShape && landscapeOk && portraitOk) {
    return layouts;
  }
  var next = RtCanvasLayouts(
    list: merged,
    activeId: layouts.activeId,
    activeIdPortrait: layouts.activeIdPortrait,
  );
  if (!merged.any((p) => p.id == next.activeId)) {
    next = next.withActiveFor(
      kRtCanvasOrientLandscape,
      kRtCanvasPresetTouchpad,
    );
  }
  final portraitBad =
      next.activeIdPortrait.isNotEmpty &&
      !merged.any(
        (p) =>
            p.id == next.activeIdPortrait &&
            rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p),
      );
  if (portraitBad) {
    next = RtCanvasLayouts(
      list: next.list,
      activeId: next.activeId,
      activeIdPortrait: '',
    );
  }
  return next;
}
