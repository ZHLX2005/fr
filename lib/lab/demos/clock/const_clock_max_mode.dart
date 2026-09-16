/// Clock max 模式的常量。
///
/// 语义：按 `LabClock.parentId` 的血缘链合并 —— clock 网格里一条链合并成一张
/// 卡（中央取链上最大时长），记录区一条链折叠成一行（取链内实际时长最大者）。
/// 旧版"按 title 聚合显示个人最佳 BP"的口径已作废。
library;

/// Max 模式开关的 UI 文案。
const String kClockMaxModeLabel = 'max 模式';

/// Max 模式副标题：提示用户按血缘链合并。
const String kClockMaxModeHint = '按链合并 · 显示链上最长';

/// 合并卡中央数字为"链上最大目标时长"时的角标。
const String kClockChainMaxBadge = '链上最长';

/// 空聚类时的兜底文案。
const String kClockMaxModeEmpty = '暂无记录。完成一次即可按链折叠。';

/// 孤儿行标题：所属 clock 已被删除、但记录仍在的那些历史记录汇总行。
const String kClockChainOrphanTitle = '已删除的时钟';

/// 孤儿行的分组 id。不可能是 uuid，避免与真实 clock id 碰撞。
const String kClockOrphanChainId = '__orphan__';

/// 编辑器"设置"区：新的根时钟开关。
const String kClockNewRootSwitchLabel = '新的根时钟';
const String kClockNewRootSwitchHintOn = '另起一条链，不参与 max 合并';
const String kClockNewRootSwitchHintOff = '并入来源时钟的链，max 合并取最大';

/// 记录折叠行左侧角标："N 条"。
String clockRecordCountLabel(int count) => '$count 条';

/// 合并卡右上角标："N 个"（一张卡代表几个 clock）。
String clockChainSizeLabel(int size) => '$size 个';
