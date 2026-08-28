// lib/lab/demos/cowrite_lua/cowrite_constants.dart
// Co-Write Notebook — 常量（参考 jungle_chess_lua 的常量拆分）

/// relay 服务端地址（与其他 7 个 Lua 房间游戏共用）。
const String kCoWriteRelayUrl = 'http://47.110.80.47:8988';

/// device_id 前缀（区分游戏，防跨游戏窜台）。
const String kCoWriteDevicePrefix = 'cw-';

/// 最大协作者数：2 人（"双人协作"语义）。
const int kCoWriteMaxPlayers = 2;

/// 顶部工具栏固定高度（房间号 / 广播状态 / 操作按钮）。
const double kCoWriteToolbarHeight = 44.0;

/// 选项行（自动广播 / 自动对齐 toggle）固定高度 —— 防止出现/消失撑动布局。
const double kCoWriteOptionRowHeight = 56.0;

/// 底部状态条固定高度（玩家列表 / 我的首行）。
const double kCoWriteStatusBarHeight = 36.0;

/// 编辑器最小行数（用于首行广播：空文本时"首行"= 第 1 行）。
const int kCoWriteEditorMinLines = 1;

/// 编辑器最大字符数（防止单端灌爆 context）。
const int kCoWriteEditorMaxChars = 20000;

/// 编辑 → 服务端的 debounce 时长（避免每键一发请求）。
const Duration kCoWriteEditDebounce = Duration(milliseconds: 250);

/// 滚动位置 → 首行行号 的 debounce（避免滚动事件高频触发广播）。
const Duration kCoWriteBroadcastDebounce = Duration(milliseconds: 300);

/// 本地参考存储 key 前缀（按房间号区分）。
const String kCoWriteReferencePrefix = 'cowrite_lua.reference.';

/// 工具栏/按钮颜色（走主题，但保留集中常量以便维护）。
const double kCoWriteToolbarRadius = 12.0;
const double kCoWriteEditorRadius = 16.0;
