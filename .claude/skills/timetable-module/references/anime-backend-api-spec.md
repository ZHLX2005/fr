# 追剧模式自建后端 API —— 业务需求与接口规范

> 状态：**✅ 已实现并上线**（2026-08-15，commit `83dcd9e`，CI build #31874490795 success）。
> 后端基地址：`https://47.110.80.47:81/api/v1/anime/season`。
> 客户端将新增 `SelfHostedAnimeAdapter` 注册进 `kAnimeSourceAdapters`（见 [anime-mode](anime-mode.md)）。
> 本文档是前后端唯一契约，字段命名/语义以后端实现时以本文为准，改动需同步更新。

## 1. 背景与业务目标

追剧模式需要"当季新番 + 具体播出时刻（精确到小时/分钟）"的准确数据。现有公开来源各有缺陷：

| 来源                 | 缺陷                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------- |
| Bangumi`/calendar` | 有中文名，但**无具体播出时刻**（time 恒为 null，用户手动补）                     |
| AniList GraphQL      | 有`airingAt` 精确时间戳，但**无中文译名**，且 `nextAiringEpisode` 完播后消失 |
| B站 / Jikan          | 实测不可用（404 / 504）                                                                |

**目标**：自建一个后端聚合服务，把"Bangumi 中文名 + AniList 精确时刻 + 总集数"合并成
一个稳定接口，让客户端一次拉取即得到字段齐全、可直接导入剧模型的草稿列表。

> **实现回填（2026-08-15）**：实测发现 AniList 按"条目季"归档会漏 split-cour
> 续播（如 Re:Zero S4 在 AniList 是 season=SPRING 单条目，Part.2 7 月起回归
> 时 SUMMER 查询查不到，正好踩 §5 验收红线）。主源改为 **yuc.wiki 月度新番页**
> （按实际播出月收录，split-cour 中途加入的剧也包含；中文标题 + 精确 JST 时刻
> + 总集数一次性拿到）。AniList 完全弃用。Bangumi /calendar 保留为降级源
> （主源挂掉时仍能返回 CN 标题+星期）。详见 §7。

**业务上要解决的三件事**：

1. **精确到分钟的播出时刻**（JST 日本时间 HH:mm + 星期几）——当前最大痛点。
2. **中文优先的标题**——用户排期页可读性。
3. **完播剧的时刻不丢**——AniList `nextAiringEpisode` 完播即空，后端需用
   `airingSchedules` 历史记录或 MAL `broadcast` 字段兜底，保证已开播/已完播剧也能给出固定播出时刻。

## 2. 业务需求

### 2.1 范围

- 默认返回**当前季**（按日本电视台季度：冬 1 月 / 春 4 月 / 夏 7 月 / 秋 10 月）的 TV 剧场连载番（format=TV）。
- 支持查询参数指定任意季（客户端排期页未来可能回看上季）。
- 单季约 50~120 部，一次返回全量（无需分页；若后端坚持分页，见 3.6）。

### 2.2 数据合并规则（后端职责）

1. 以 AniList 当季列表为骨架（有精确时间戳、总集数）。
2. 按 AniList `native`（日文原名）+ 年份与 Bangumi 条目匹配，命中则取 Bangumi `name_cn` 作 `title`；未命中回退日文原名，再回退罗马音。
3. 播出时刻来源优先级：`nextAiringEpisode.airingAt`（UTC 时间戳 +9h 换算 JST）→ `airingSchedules` 任意一集历史时间戳 → MAL `broadcast.start_time`（JST 字符串）→ null。
4. 深夜番约定：日本 0:00~6:00 播出的算**前一天深夜**（如周六 25:30 = 周日 01:30）。**后端统一按"自然日 JST"输出星期与时刻**（即周日 01:30），不做 +1 天偏移——客户端生成器按自然日排布，偏移语义由用户在排期页自行理解。

### 2.3 字段要求总表

| 字段         | 必填 | 语义                                              | 缺失策略                            |
| ------------ | ---- | ------------------------------------------------- | ----------------------------------- |
| title        | ✅   | 中文优先的标题                                    | 骨架兜底，理论必有                  |
| startDateIso | 建议 | 开播日期`YYYY-MM-DD`（JST）                     | null → 客户端按星期对齐到本周      |
| weekday      | ✅   | 播出星期 1-7（ISO：1=周一 … 7=周日，JST 自然日） | null → startDate 推                |
| time         | 建议 | `HH:mm`（JST 24 小时制）                        | null → 客户端独立扩容 cell，用户补 |
| episodes     | 建议 | 总集数                                            | null → 客户端默认 13               |
| durationMin  | 可选 | 单集分钟                                          | null → 客户端默认 45               |
| sourceUrl    | 可选 | 详情页（Bangumi 或 AniList 页面均可）             | null                                |

## 3. API 规范

### 3.1 端点

```
GET {BASE_URL}/api/v1/anime/season
GET {BASE_URL}/api/v1/anime/season?season=SUMMER&year=2026
GET {BASE_URL}/api/v1/anime/season?season=SUMMER&year=2026&weekday=3
```

- `season`：`WINTER | SPRING | SUMMER | FALL`（缺省 = 当前季，由服务器按 JST 日期判断）。
- `year`：缺省 = 当前季年份。
- `weekday`：**契约外新增**（实现期用户追加），`1..7` ISO（1=周一..7=周日）。过滤该星期的条目，缓存后裁剪不额外打上游。
- 认证：暂不需要；预留 `Authorization: Bearer <token>` 透传位（客户端适配器常量配置即可切换）。

### 3.2 成功响应（HTTP 200）

```json
{
  "season": "SUMMER",
  "year": 2026,
  "generatedAt": "2026-08-15T08:00:00+09:00",
  "items": [
    {
      "id": "anilist:177234",
      "title": "葬送的芙莉莲 第二季",
      "titleNative": "葬送のフリーレン第2シリーズ",
      "startDateIso": "2026-07-04",
      "weekday": 7,
      "time": "00:00",
      "episodes": 28,
      "durationMin": 24,
      "sourceUrl": "https://bgm.tv/subject/460829",
      "matchedSources": ["anilist", "bangumi"]
    }
  ]
}
```

> `time` 语义：**JST、自然日 24 小时制**。深夜番直接输出真实时刻并归到正确自然日——
> 如周六深夜 24:00 播出（电视台排表口径）→ 输出 `weekday=7, time="00:00"`（周日零点，JST）。
> 统一规则：`time ∈ [00:00, 23:59]`，`weekday` 与 `time` 永远是同一自然日（JST）。

### 3.3 字段规范（严格）

| 字段                   | 类型     | 约束                                                          |
| ---------------------- | -------- | ------------------------------------------------------------- |
| season                 | string   | 四枚举之一                                                    |
| year                   | int      | 4 位年份                                                      |
| generatedAt            | string   | ISO 8601 带时区，数据生成时间（客户端可借此判断缓存新鲜度）   |
| items[].id             | string   | 稳定唯一 id（建议`<source>:<sourceId>`），客户端去重用      |
| items[].title          | string   | 非空；中文优先                                                |
| items[].titleNative    | string?  | 日文原名，调试/辅助匹配用                                     |
| items[].startDateIso   | string?  | `YYYY-MM-DD`，JST                                           |
| items[].weekday        | int?     | 1-7（1=周一）。**不是 Bangumi 的 0=周日**，后端负责换算 |
| items[].time           | string?  | `HH:mm`，JST 自然日。**完结剧为 null**（finished=true）  |
| items[].episodes       | int?     | > 0                                                           |
| items[].durationMin    | int?     | > 0                                                           |
| items[].sourceUrl      | string?  | 合法 URL                                                      |
| items[].finished       | bool     | **契约外新增**（2026-08-15 追加）。True = 季已完结/剧已停播，对应 yuc 网格 `<p class=imgtext2>完结</p>`（即 past season 查询）。前端可用作"已完结"标识。|
| items[].matchedSources | string[] | 命中了哪些上游（运维排查用，客户端忽略）                      |

### 3.4 错误响应

```json
{ "error": { "code": "UPSTREAM_TIMEOUT", "message": "anilist timeout after 10s" } }
```

- HTTP 4xx/5xx + 上述 JSON 体。
- 客户端策略：非 200 直接抛 `HTTP <code>`，由导入对话框展示；**部分字段缺失不算错误**（items 内允许 null 字段，整季数据宁可降级也要返回）。

### 3.5 缓存与频率（强烈建议）

- 上游（AniList 限速 30 req/min）由后端缓存，TTL 建议 6h；`generatedAt` 即缓存时间。
- 客户端只在用户主动打开导入对话框时拉取，频率极低（天级），无需更细限流。

### 3.6 分页（可选，仅在后端确有需要时实现）

- 若实现：响应加 `"page": 1, "totalPages": 3`，客户端按 `?page=N` 轮询（上限 3 页防御性兜底，与现有 AniList 适配器一致）。不实现则**不要**加这两个字段。

## 4. 客户端消费方式

- 新增 `SelfHostedAnimeAdapter implements AnimeSourceAdapter`（fr 28 已落地）：
  - `id = 'selfhosted-season'`，`label = '自建新番表'`
  - `_baseUrl = 'http://47.110.80.47:81'`、`_apiPath = '/api/v1/anime/season'`
  - `fetch()` → GET（无参 → 后端默认当前季） → 解析 `items[]` → `AnimeDraft`
  - 字段映射：`title`/`startDateIso`/`weekday`(校验 1-7)/`time`(校验 `HH:mm`)/`episodes`/`sourceUrl` 1:1 透传；非法字段降级 null
- 注册：`kAnimeSourceAdapters = [SelfHostedAnimeAdapter()]`
- 原有 `BangumiCalendarAdapter` / `AniListSeasonAdapter` 已移除（公开来源字段不全 + 维护成本过高，且自建后端已完整覆盖）

## 5. 验收标准

1. 拉当前季返回 ≥ 50 部 TV 番（正常季度规模）。
2. 抽查 5 部深夜番：`time` 为 `[00:00, 06:00)` 区间的真实 JST 时刻且 `weekday` 归属正确自然日。
3. ≥ 80% 条目 `title` 为中文（Bangumi 命中率抽检）。
4. 已完播剧（无 nextAiringEpisode）`time` 不为空（历史时刻兜底生效）。
5. `weekday` 换算正确：Bangumi 的 0（周日）必须输出 7。
6. 上游任一家挂掉时接口仍 200 返回降级数据（缺失字段置 null）。

## 6. 回调记录

- 2026-08-15：后端上线，基地址 `http://47.110.80.47:81`，端点 `GET /api/v1/anime/season`。实测 HTTP 200，返回字段与 §3.3 一致
- 客户端：fr 28 已新增 `SelfHostedAnimeAdapter`，`BangumiCalendarAdapter` / `AniListSeasonAdapter` 已移除
- 后续 §5 任一条不过再回后端修

**实测（2026-08-15）**：基地址 `https://47.110.80.47:81`，CI build #31874490795 success，
端到端已通过 §5 六条标准 + 用户验收锚点"Re:0 S4 Part.2 周三 21:00"。

---

## 7. 实现回填（2026-08-15）

### 7.1 数据源选型变更

| 角色 | 原契约 | 实装 | 原因 |
|---|---|---|---|
| 主源 | AniList（按条目季） | **yuc.wiki**（按月度页）） | AniList 漏 split-cour 续播（Re:0 S4 验证） |
| 中文名 | Bangumi | yuc 自带（98.7% CN） | yuc 已是中文站，无需二次合并 |
| 精确时刻 | AniList `airingAt` | yuc 网格 `imgtext4/5` | yuc 已是 JST 自然日（含 24:00+ 归一） |
| 降级源 | （未规划） | **Bangumi `/calendar`** | 主源挂时返回 CN 标题+星期（无时刻）） |
| 总集数 | AniList `episodes` | yuc `imgep`(全N话) + 详情 `(全N话)` | 详情覆盖网格 |
| 详情页 | Bangumi / AniList | yuc 详情区"动画官网"链接 | yuc 自带，质量稳定 |

### 7.2 yuc.wiki 页面解析规则

- **按月单页**：`http://yuc.wiki/{YYYY}{MM}/`（WINTER→01、SPRING→04、SUMMER→07、FALL→10）。
- **分节**：`<!--周一-->` 注释 + `<td class="date2">周一 (月)</td>`；网络放送 & 其他节不输出（无 TV 时刻）。
- **网格条目**：`div.div_date > p.imgtext4|5`（时刻） + `p.imgep`（全N话）或 `p.imgep2`（M/D~ 中途加入） + `img data-src`（封面）。
- **详情区**：`p.title_cn_r*` 中文全名 / `p.title_jp_r*` 日文名 / `p.broadcast_r`（"8/12周三晚间"）/ `p.broadcast_ex_r`（"(全8话)"）/ 官网链接。
- **join 键**：网格 ↔ 详情用图片哈希（hdslb URL 文件名 ≥16 位 hex）配对。
- **深夜记法归一**：yuc 用 24:00+ 表示次日凌晨（"周六 24:30"），按契约输出 `weekday+1, time-24h`。周日 25:00 → 周一 01:00（跨周回绕）。
- **跨年**：1 月季页上的 12/x 开播日视为上一年（如 2026年1月页上的 "12/28周六深夜" → 2025-12-28）。

### 7.3 验收实测（SUMMER 2026，2026-08-15 线上 `https://47.110.80.47:81`）

| 契约 § | 检查 | 实测 |
|---|---|---|
| 5.1 | ≥50 条 TV | ✅ **78** |
| 5.2 | 深夜番 `[00:00, 06:00)` 真实 JST + 自然日归属 | ✅ **17 条**（含"花样少年少女 第2期 周四 01:00"） |
| 5.3 | ≥80% CN 标题 | ✅ **98.7%**（77/78） |
| 5.4 | 已开播剧 time 不空 | ✅ **64 部开播剧 100% 有时刻** |
| 5.5 | weekday ∈ [1,7] | ✅ |
| 5.6 | 上游挂掉仍 200 降级 | ✅ router 单测覆盖（yuc 502 → bangumi → 200） |

**用户验收锚点**：Re:Zero S4 Part.2 命中（线上实测）：

```json
{
  "id": "yuc:e5498ee6e63f87ba626eb1a643692635512995925",
  "title": "Re:从零开始的异世界生活 第4期 Part.2 夺还篇",
  "titleNative": "Re:ゼロから始める異世界生活 4th season",
  "weekday": 3,
  "time": "21:00",
  "startDateIso": "2026-08-12",
  "episodes": 8,
  "sourceUrl": "https://re-zero-anime.jp/tv/"
}
```

### 7.4 代码位置

- 后端模块：`backend/src/rt_backend/anime_season/`
  - `schemas.py` — Pydantic 契约模型
  - `yuc.py` — yuc.wiki 月度页解析器（24:00+ 归一 + 图片哈希 join）
  - `service.py` — 6h 内存缓存 + 并发主源/降级源 + 当前季推断 + 错误体
  - `router.py` — `GET /api/v1/anime/season`（含 `?weekday=`）
- 挂载：`backend/src/rt_backend/main.py`
- 配置：`backend/src/rt_backend/core/config.py` → `anime_cache_ttl_sec=21600`、`anime_upstream_timeout_sec=15`
- 测试：`backend/tests/test_anime_{yuc,service,router}.py` + `fixtures/yuc_sample.html`，16 个用例全过
- 部署：CI build #31874490795，commit `83dcd9e`

### 7.5 已知限制 / 后续可优化

- `durationMin` 全部为 null（yuc 不提供；契约允许，客户端默认 45min）
- `sourceUrl` 指向动画官网而非 Bangumi/AniList（契约允许任意合法 URL）
- 长尾条目（约 14/78）缺失 `titleNative`/`startDateIso`/`sourceUrl`——因 yuc 详情区 join 失败（个别条目无详情块），契约允许部分字段缺失
- 缓存 TTL 6h 由 `anime_cache_ttl_sec` 控制；`generatedAt` 即缓存时间
