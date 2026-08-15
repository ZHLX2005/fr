# 追剧/番模式专项（anime-mode）

> 特化指导：只在扩展/修改追剧模式时读取。主干架构见主 SKILL.md。

## 架构演进（fr 27 后）：剧模型 SSOT，非 DSL 快照

**追剧模式的唯一数据源 = 剧模型列表（AnimeSeriesDraft），DSL 由它自动派生。**

```
剧模型(AnimeSeriesDraft[]) ──CRUD──> store 自动 buildAnimeDsl
     │                                  │
     └─ 存储: box/record animeSeries     └─> updateConfig + 重建课程（自动应用）
```

- **不再有**"生成 DSL 预览 → 手动应用/覆盖"的体验；每次剧变更自动重算并应用
- API 导入 = 追加进剧模型（不覆盖自定义剧）
- DSL 只有只读预览入口（排期编辑页「查看 DSL」按钮）

## 数据模型

- `AnimeSeriesDraft`（anime_dsl_generator.dart）：id + title/startDateIso(选填)/weekday(1-7)/time(HH:mm)/episodes(**选填**)/durationMin，`toJson/fromJson` 完整序列化（缺字段回退：weekday=1, durationMin=45；episodes 缺省为 null）
- **episodes=null = 长期番（年番）**：`visibleInCycles=null` 填满所有周期，**不参与周期数计算**；周期数由有界剧决定，全无界/存在无界时用 `fallbackCycles`（store 自动派生传当前 config.cycleCount）
- 存储：`timetable_anime_series` box（default 空间，key='series'）/ 空间 record 的 `animeSeries` 字段（新空间）；已注册 StorageRegistry（面板名「追剧剧集」）
- repo 接口：`loadAnimeSeries()` / `saveAnimeSeries(List<AnimeSeriesDraft>)`（按激活空间路由）
- store：`state.animeSeries` + `addAnimeSeries` / `updateAnimeSeries`(按 id 替换) / `deleteAnimeSeries` / `importAnimeSeries`(追加)；每个 CRUD → 保存 → `_autoApplyAnimeDsl()`（剧列表为空时不派生）

## 生成器（anime_dsl_generator.dart，纯函数可测）

`buildAnimeDsl(List<AnimeSeriesInput>) → {config, items, dsl}`（fr 28 简化 + 鲁棒化）：
1. **每部剧独立占一个 slot**（不再按时段堆叠避免视觉覆盖）。左侧顺序（fr 28 调整）：
   - **未补时间的剧排最前**，每部独占空标签 slot（渲染回退序号 1,2,3...），按输入顺序
   - **有时间剧按开始时间（HH:mm）升序排在后面**；同时刻冲突的多部剧（桶内按 weekday 升序、再按输入顺序）**全部加 "(1)" "(2)" 后缀**保证相邻行可区分；独有时刻保持纯净
2. 起始日期 = 所有合法 startDateIso 中最早那天对齐周一；全部为空/非法时回退本周一（修复 Slime 等 startDateIso=null 触发的 `DateTime.parse` 崩溃）
3. 每部剧 dayOfCycle 优先由 startDateIso 推算（weekday 字段冗余但保留兼容）；weekOffset = (start - anchor_monday).inDays ~/ 7；空 startDate 时 weekOffset=0
4. cycleCount = 最长覆盖（自动膨胀/收缩，无需手动配置周期）
5. 输出 config（daysPerCycle=7 / **leftLabelMode=2 + slotLabels**：左侧 cell 为自定义标签模型，标签=开始时间标识，不走时间段模型拼结束时间；fr 28）+ items + DSL 文本（可回灌 parseDsl 还原，有单测闭环）

`backfillStartDate(currentEpisode, weekday)`：当前第 N 期 → 从最近播出日回推 (N-1) 周（反推开播日期）。

## 适配层（anime_source_adapter.dart）

```dart
abstract class AnimeSourceAdapter {
  String get id;      // 唯一 id
  String get label;   // 展示名
  Future<List<AnimeDraft>> fetch();
}
// 登记: kAnimeSourceAdapters = [SelfHostedAnimeAdapter()];
```

- `AnimeDraft`：title/startDateIso/weekday/time/episodes/sourceUrl，**可缺省**（后端字段已尽量补齐，缺字段时用户在排期页补）
- 已登记来源：`SelfHostedAnimeAdapter`（自建聚合后端，详见 [anime-backend-api-spec](anime-backend-api-spec.md)）。后端已完成 Bangumi 中文名 + AniList `airingAt` 精确时刻 + MAL `broadcast` 兜底 + 完播剧时刻补齐。原先的 `BangumiCalendarAdapter` / `AniListSeasonAdapter` 已在 fr 28 移除（公开来源不稳定性 + 字段不全，已被自建后端替代）
- 导入对话框来源下拉仅剩「自建新番表」一项；空 time 导入为 `time=null`，生成器为每部独立扩容 cell（输入顺序在前，标签回退序号），用户补时间后自动归并
- **水平泛化方向**：AnimeDraft → PeriodicEventDraft（直播/比赛/日程/影视更新），适配器跨领域复用

## 排期编辑页（timetable_anime_editor_page.dart）

- 垂直时间轴视图：按播出时间排序，行 = 时间标签 + 剧信息卡（点卡片编辑/删除）
- 编辑对话框字段全是"剧的语言"：剧名/开播日期(或当前第N期反推)/星期几/几点播出/总集数/每集分钟
- 顶部自动派生摘要条（实时显示 起始/每天行数/总周数/剧数）——已自动应用
- 入口：设置页追剧模式数据来源区

## 高级设置与剧模式的关系

- 剧模式的行列周期全部自动派生，**不需要**高级设置页的周期/日期配置（高级设置只服务学校/通用）
- 追剧模式下高级设置仍可调左侧指示显示控制（leftLabelMode 已由生成器设为自定义标签模式，标签=开始时间；可在高级设置微调宽度）

## 追剧专项错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 每次添加剧手动生成 DSL 覆盖 | 前次自定义丢失/覆盖 | 剧模型 CRUD → store 自动派生 |
| API 导入直接 upsert 课程 | 覆盖已有剧 | drafts → importAnimeSeries 追加进模型 |
| 剧模型变更后手动调 updateConfig 不调 _autoApplyAnimeDsl | 显示与模型不一致 | 统一走 store CRUD（内含自动派生） |
| 非追剧模式调用 addAnimeSeries | 自动派生会把模式切回追剧 | 排期编辑仅追剧模式可达 |
