// lib/lab/demos/remotetype/rt_canvas_presets.dart
//
// 画布内置布局预设（与 docs/prototypes/rt-canvas-gamepad.html LAYOUTS 同源）：
//   · 游戏 = 纯手柄（vpad_dpad + vpad_button/trigger）
//   · 键盘 = 全键盘（hotkey，Fn 行折叠）
//   · 输入页 = 竖屏默认：连接后落到的打字页本身（工具行 + 快捷键托盘 +
//     composer），横竖共用同一会话；竖屏激活兜底就是它
//   · 触控屏 = 满屏触摸板（mouse；横竖屏双朝向可用）
// 用户可改；改后存盘。自定义无数量上限。
// 「默认布局」「触控屏 · 竖」已退役——ensure 会剔除旧内置条目。

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasModuleComposer,
        kRtCanvasModuleDpad,
        kRtCanvasModuleKb,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        kRtCanvasPresetGame,
        kRtCanvasPresetInputPage,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
        rtCanvasLayoutUsableIn;

/// 内置预设列表（按 UI 展示顺序）。用户可改；改后存盘，下次启动沿用用户版。
const List<RtCanvasNamedLayout> kRtCanvasBuiltinPresets = [
  // 1. 游戏：纯手柄——左拖动轮盘 + 右 ABXY/肩键（锚点 = 原型 LAYOUTS.game）。
  //    信号走 vpad 通道；hideShortcuts：快捷键按钮区归手柄模块。
  RtCanvasNamedLayout(
    id: kRtCanvasPresetGame,
    name: '游戏布局',
    builtIn: true,
    data: RtCanvasLayout(
      hideShortcuts: true,
      modules: {
        kRtCanvasModuleDpad: RtCanvasAnchor(
          visible: true,
          x: 0.21,
          y: 0.54,
          w: 0.22,
          h: 0.52,
        ),
        kRtCanvasModuleVpad: RtCanvasAnchor(
          visible: true,
          x: 0.765,
          y: 0.53,
          w: 0.36,
          h: 0.70,
        ),
      },
    ),
  ),
  // 2. 键盘：全键盘（Fn 行折叠，按键即发 hotkey）。无输入条、无内嵌触摸板。
  RtCanvasNamedLayout(
    id: kRtCanvasPresetKeyboard,
    name: '键盘布局',
    builtIn: true,
    data: RtCanvasLayout(
      hideShortcuts: true,
      modules: {
        kRtCanvasModuleKb: RtCanvasAnchor(
          visible: true,
          x: 0.50,
          y: 0.55,
          w: 0.94,
          h: 0.82,
        ),
      },
    ),
  ),
  // 3. 输入页（竖屏默认）：连接后落到的打字页本身——满屏 composer 模块
  //    （工具行 + 快捷键托盘 + 输入框）。竖屏激活兜底取它（列表里第一套
  //    竖屏可用内置）；hideShortcuts：托盘在模块内，画布按钮区不重复渲染。
  RtCanvasNamedLayout(
    id: kRtCanvasPresetInputPage,
    name: '输入页',
    builtIn: true,
    orientation: kRtCanvasOrientPortrait,
    data: RtCanvasLayout(
      hideShortcuts: true,
      modules: {
        kRtCanvasModuleComposer: RtCanvasAnchor(
          visible: true,
          x: 0.50,
          y: 0.50,
          w: 1.0,
          h: 1.0,
        ),
      },
    ),
  ),
  // 4. 触控屏：满屏触摸板（原型 full；不锁横屏 → 竖屏也可用）。
  RtCanvasNamedLayout(
    id: kRtCanvasPresetTouchpad,
    name: '触控屏布局',
    builtIn: true,
    data: RtCanvasLayout(
      modules: {
        'touchpad': RtCanvasAnchor(
          visible: true,
          x: 0.50,
          y: 0.50,
          w: 1.0,
          h: 1.0,
        ),
      },
    ),
  ),
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
