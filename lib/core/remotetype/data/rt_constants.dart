// lib/core/remotetype/data/rt_constants.dart
//
// RemoteType（远程输入）lab demo 常量。
// 直连模式：唯一后端是 mn-rt 的 server.js（固定部署地址内置，用户不填）。

import '../../../api/remotetype/remotetype_config.dart';

/// mn-rt server 固定部署地址（server 托管的网页控制台同源）。
///
/// 值来自 `lib/api/remotetype/`——规范检测项 5 要求 URL 只出现在 api 层。
/// demo 这边再抄一份字面量，就会有"改了常量却只改了一处"的第二个真地址。
const String kRemoteTypeServerUrl = RemoteTypeConfig.serverBaseUrl;

/// 房间号字母表：与 mn-rt rt-crypto.js 的 ROOM_ALPHABET 逐字符一致。
/// 直连模式下派生房间号不再用于路由，仅作为 AAD 上下文标签（两端一致即可）。
const String kRtRoomAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 房间号长度（从派生字节映射而来）
const int kRtRoomCodeLen = 5;

/// PBKDF2 参数（key 预期高熵随机，迭代只求抹平实现差异）
const int kRtPbkdf2Iterations = 10000;
const String kRtPbkdf2Salt = 'RT1-pair';

/// HKDF info 标签（两端逐字节一致，改动必须同步 mn-rt 并重出对拍向量）
const String kRtInfoRoom = 'RT1-room';
const String kRtInfoSalt = 'RT1-salt';
const String kRtInfoKeyPhoneToPc = 'RT1-key-phone-pc';
const String kRtInfoKeyPcToPhone = 'RT1-key-pc-phone';

/// AAD 协议前缀
const String kRtAadPrefix = 'RT1';

/// 方向标签
const String kRtDirPhoneToPc = 'p2c';
const String kRtDirPcToPhone = 'c2p';

/// 输入同步防抖（ASR partial 高频变更）
const Duration kRtSyncDebounce = Duration(milliseconds: 250);

/// demo slug（fr://lab/demo/remotetype）。demo 注册与 DemoSessionHost 托管
/// 共用一份——两处各写字面量会出现「托管挂在 slug A、注册是 slug B」的静默失联。
const String kRemoteTypeDemoSlug = 'remotetype';

/// 全文上限（与 mn-rt sanitize 截断上限一致）
const int kRtMaxTextLength = 5000;

/// 构建标识：联调时核对手机上跑的是不是最新修复（每次改动 demo 逻辑时递增）
const String kRtBuildTag = 'b12-no-3finger';

// ── 触摸板（v0.6.0+ 两端协议）──────────────────────────────────────────
// 手势 → PC 鼠标事件的全部调参常量。单位一律逻辑像素（logical px）与毫秒。

/// 单指点按判定：位移超过即转为移动/滚轮，不算点按。
const double kRtPadTapSlop = 22.0;

/// 单指点按最长时长（毫秒）：超过按住拖拽阈值走拖拽分支。
const int kRtPadTapMaxMs = 220;

/// 按住该时长后才开始移动 → 左键拖拽（press 后跟随移动）。
const int kRtPadDragLongPressMs = 320;

/// 双指点按（右键）的最长时长：两指静置很久再抬手不算右键。
const int kRtPadTwoFingerTapMaxMs = 420;

/// 滚轮一格（notch）对应的指头位移。
const double kRtPadScrollPxPerTick = 48.0;

/// 抬手速度超过该值（px/ms）触发惯性滚动；衰减到该值以下停止。
const double kRtPadFlingStartPxMs = 0.35;
const double kRtPadFlingStopPxMs = 0.03;

/// 惯性速度每 16ms 的衰减系数（0.94 ≈ 400ms 内从 0.35 衰到停止）。
const double kRtPadFlingDecayPer16Ms = 0.94;

/// 指针加速度：慢速精细（<1）、快速长距离（>1）。piecewise 二次缓入，
/// 由 [rtPadAccelFactor] 实现，参数固定不设常量（调参改函数体）。

/// 灵敏度用户偏好范围与缺省（乘在加速度系数上）。
const double kRtPadSensitivityDefault = 1.0;
const double kRtPadSensitivityMin = 0.4;
const double kRtPadSensitivityMax = 2.5;

/// 移动/滚动增量的发送合批间隔（毫秒）。≈33Hz：低于人手感知阈值，
/// 高于互联网链路抖动下的包率红线；增量在两侧都可再生合并。
const int kRtPadSendTickMs = 30;

/// 快捷键预设（v0.5.4+ 两端协议）：数组末位是主键、其余是修饰键，

/// 快捷键预设（v0.5.4+ 两端协议）：数组末位是主键、其余是修饰键，
/// 与 mn-rt rt-align.js 的 hotkey 分支约定一致（['win','r'] = Win+R）。
///
/// 修饰键合法值见 mn-rt parse_modifier_name：shift / ctrl / alt / meta
/// （别名 win / cmd / super）；主键见 parse_key_name（return / tab / f1-f12 /
/// 单个 ASCII 字符等）。这里只列两端都认识的名字，新增预设先查 PC 端白名单。
///
/// 每条快捷键仍是一条单 chord 预设；序列宏（多条 chord + 毫秒间隔）在
/// 运行时由前端循环 `syncHotkey` + sleep 实现，协议层不动。
const List<List<String>> kShortcutPresets = [
  ['win', 'r'],
  ['win', 'v'],
  ['win', 'd'],
  ['win', 'e'],
  ['win', 'l'],
  ['win', 'i'],
  ['alt', 'tab'],
  ['ctrl', 'shift', 't'],
  ['f5'],
  ['ctrl', 'shift', 'escape'],
];

/// 预设的人话标签（UI 显示用，与 kShortcutPresets 一一对应）。
const List<String> kShortcutLabels = [
  'Win+R 运行',
  'Win+V 剪贴板',
  'Win+D 桌面',
  'Win+E 资源管理器',
  'Win+L 锁屏',
  'Win+I 设置',
  'Alt+Tab 切窗',
  'Ctrl+Shift+T 恢复标签',
  'F5 刷新',
  'Ctrl+Shift+Esc 任务管理器',
];

/// 序列宏相邻 chord 之间的间隔（毫秒）。用户自调，0 = 立即接龙。
///
/// 范围刻意卡在 0..1000：超过 1s 的"等待"已经偏向手动操作而不是宏，继续往大
/// 走会把 slider 调成时间机器；25ms 一档做心率。
const int kRtShortcutIntervalDefaultMs = 80;
const int kRtShortcutIntervalMinMs = 0;
const int kRtShortcutIntervalMaxMs = 1000;
const int kRtShortcutIntervalDivisions = 40; // 25ms/档

/// 是否被 UI 当作「单组紧凑外观」（隐藏计数与间隔 badge）。
/// chords.length==1 且 intervalMs==0 → 走旧 chip 形态。
const int kRtShortcutCompactChordCap = 1;
