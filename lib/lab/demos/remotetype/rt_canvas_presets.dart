// lib/lab/demos/remotetype/rt_canvas_presets.dart
//
// 横屏画布内置布局预设：默认 / 游戏 / 键盘 / 触控屏 四套（代码内置，
// 可被用户在画布里自由编辑；编辑后存为「用户改过的版本」，下次启动沿用）。
// 用户从「布局」sheet 复制当前为新自定义，做个人编排；自定义无数量上限。
//
// 与「键盘布局」/「触控屏布局」等命名保持口语（用户记忆点 = 用途，
// 不是几何）。每个预设只定义模块锚点（含宽高 + 显隐），按钮位留空
// ——首跑按候选槽自动找位（与「游戏布局」玩第一次的体验一致）。

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasPresetDefault,
        kRtCanvasPresetGame,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad;

/// 内置预设的「未指定宽高时」兜底规格（保持与原画布默认值一致）。
const double _kPadDefW = 0.54, _kPadDefH = 0.84;
const double _kInputDefW = 0.46, _kInputDefH = 0.18;

/// 内置预设列表（按 UI 展示顺序）。用户可改；改后存盘，下次启动沿用用户版。
const List<RtCanvasNamedLayout> kRtCanvasBuiltinPresets = [
      // 1. 默认：左手触摸 + 右上输入 + 右侧按钮区（原手柄形态）。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetDefault,
        name: '默认布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.27,
              y: 0.55,
              w: _kPadDefW,
              h: _kPadDefH,
            ),
            'input': RtCanvasAnchor(
              visible: true,
              x: 0.73,
              y: 0.16,
              w: _kInputDefW,
              h: _kInputDefH,
            ),
          },
        ),
      ),
      // 2. 游戏：触摸板主占、输入框隐藏、按钮全开。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetGame,
        name: '游戏布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.30,
              y: 0.55,
              w: 0.55,
              h: 0.85,
            ),
            'input': RtCanvasAnchor(
              visible: false,
              x: 0.73,
              y: 0.16,
              w: _kInputDefW,
              h: _kInputDefH,
            ),
          },
        ),
      ),
      // 3. 键盘：底部满宽输入条为主、触摸板退居顶部小区域。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetKeyboard,
        name: '键盘布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.27,
              y: 0.20,
              w: 0.50,
              h: 0.30,
            ),
            'input': RtCanvasAnchor(
              visible: true,
              x: 0.50,
              y: 0.72,
              w: 0.96,
              h: 0.22,
            ),
          },
        ),
      ),
      // 4. 触控屏：触摸板最大化、输入框隐藏（接外部键盘时用）。
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
              w: 0.96,
              h: 0.92,
            ),
            'input': RtCanvasAnchor(
              visible: false,
              x: 0.73,
              y: 0.16,
              w: _kInputDefW,
              h: _kInputDefH,
            ),
          },
        ),
      ),
    ];
