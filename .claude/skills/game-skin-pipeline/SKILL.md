---
name: game-skin-pipeline
description: 游戏资源公开 KV 管线 —— 皮肤 / 封面 / 曲库 / 表情包四条线统一走 File API + KV public（groupId=190），从图片或音频资源到客户端免发版生效的完整链路。当要"新增/更换一套皮肤/封面/歌曲/表情包"、"更新 chess_skin:index / gomoku_skin:index / game-center_skin:index / line_song:index / emoji_*_skin:index"、"排查皮肤不生效 / 图挂了 / 曲库空白 / 表情发不出去"时触发。含可执行上传脚本与端到端 SOP。
---

# Game Skin Pipeline — 游戏资源公开 KV 管线（5 条线统一）

> 一句话：**新增资源 = 走 File API 上传拿 file_id → 拼 meta JSON → 写进 KV public（groupId=190）→ 客户端下次启动自动生效，无需发版。**

## 覆盖范围

本 skill 统一管理 5 条公开 KV 索引管线（共享同一后端 / 同一种 tag 命名约定 / 同一族脚本）：

| 管线 | KV key | tag 前缀 | 资产维度 | 事实源 / 客户端 |
|---|---|---|---|---|
| 国际象棋皮肤 | `chess_skin:index` | `chess-skin` | 12 棋子（`wK…bp`） | `lib/core/chess/skins/chess_skin_meta.dart` → `chess_skin_meta_sync.dart` |
| 五子棋皮肤 | `gomoku_skin:index` | `gomoku-skin` | 3（`black / white / board`） | `lib/core/gomoku/skins/` |
| 游戏中心封面 | `game-center_skin:index` | `game-center-skin` | 2（`small / large`，skinId = demo slug） | `lib/core/game_kit/skin/game_center_skin_spec.dart` |
| 音游「线」曲库 | `line_song:index` | `line-song` | 3（`audio / cover / chart`，谱面走 File） | `lib/core/line/io/chart_repository.dart` |
| 表情包 | `emoji_<scope>:index` | `<scope>-emoji` | 单文件（任意 `image/*` / `gif`） | `lib/core/game_kit/emoji/emoji_bundle.dart` |

加 1 条**目录发布线**（不走 File，只发 JSON array）：

| 管线 | KV key | tag | 事实源 |
|---|---|---|---|
| 游戏中心目录 | `game-center_catalog:index` | `game-center-catalog` | `lib/core/game_kit/game_center_catalog.dart` 的 `kGameCenterCatalog` |

## 何时读哪个 ref / 用哪个脚本

| 场景 | 读/用 | 路径 |
| --- | --- | --- |
| **新增一套游戏皮肤（任意 gameId）** | [[extend-sop]] §2 全流程走一遍 | `references/extend-sop.md` |
| **新增一款游戏封面（game-center）** | [[extend-sop]] §3 | `references/extend-sop.md` |
| **新增一首歌（line songs）** | [[extend-sop]] §4 | `references/extend-sop.md` |
| **新增一套表情包（任意 scope）** | [[extend-sop]] §5 + [[emoji-sop]] | `references/extend-sop.md` §5 + `references/emoji-sop.md` |
| 发布游戏中心目录（新增/下线游戏） | 跑 `tool/publish_game_center_index.dart` | `tool/publish_game_center_index.dart` |
| 上传图片/音频/表情拿 file_id | 跑 `scripts/add_<thing>.py` | `scripts/add_skin.py` / `scripts/add_emoji_pack.py` |
| 一次性给旧 chess 文件补 tag | 跑 `retag_existing.py` | `scripts/retag_existing.py` |
| 把 line 曲库从 Supabase 迁过来 | 跑 `migrate_line_from_supabase.py` | `scripts/migrate_line_from_supabase.py` |
| 理解加载链路（混合三层 + 文件地图） | [[architecture]] | `references/architecture.md` |
| 皮肤/曲库/表情不生效 → 排查 | [[extend-sop]] §6 | `references/extend-sop.md` §6 |

## 核心事实（后端能力，已实测）

| 能力 | 接口 | 鉴权 |
|---|---|---|
| 文件上传 | `POST /api/v1/files`（multipart，`file` 字段 + `key`/`accessLevel=public` + `tags[]`） | **需登录** |
| 文件下载 | `GET /files/<fileId>` | **匿名 ✅** |
| 文件补 tag | `PATCH /api/v1/files/<fileId>` body=`{tags: [...], groupId: N}`（**replace 语义**） | **需登录** |
| KV 写入 | `POST /api/v1/kv`（`visibility=public`，`groupId=190`，`tags` 可选） | **需登录** |
| KV public 匿名读 | `GET /api/v1/kv/public/<key>?groupId=<gid>` | **匿名 ✅** |
| KV 标准读 | `GET /api/v1/kv/<key>` | 需登录 ❌（勿用） |
| KV share 访问 | `GET /api/v1/kv/share/<code>` | 需登录 ❌（勿用） |
| KV tag facet | `GET /api/v1/kv/tags?groupId=<gid>` → `{tag, count}[]` | **需登录** |

> 🚨 **六个实测踩坑，勿重蹈**：
> 1. 上传路径是 `/api/v1/files`（multipart field 必须叫 `file`），**不是** `/api/v1/upload`（404）。
> 2. KV 匿名读**必须**走 `/api/v1/kv/public/<key>?groupId=N`（N≥1，用 190 shared 公共组）；标准 `/api/v1/kv/<key>` 匿名一律 401。
> 3. KV share（`/kv/share/:code`）在 MustAuth 组内，**不是**匿名通道，本管线勿用。
> 4. PATCH /files 的 `tags` 是 **replace 语义**（空数组 = 清空）；不要把整组 tags 误传成单个 tag 字符串。
> 5. File 的实际所在组不一定是 190（旧 add_skin.py 没显式 groupId，文件落在调用者默认组 23），所以 PATCH /files 不要带 `groupId` query —— 后端按 fileId 定位。
> 6. KV index 是**全量 array 覆盖**语义：合并发布是脚本内做的"读旧 → 合并 → 全量写回"；不要尝试只发增量。

## Tag Schema（2026-09 起，5 条线统一）

文件与 KV 在后端 tag 维度对齐，前端/管理工具可按 tag 维度查询。所有 5 条线遵循同一三级 tag 规则：

```
File tags（multipart tags[]=）:
  必带:   '<domain>-<kind>'                   # 例 chess-skin / gomoku-skin / game-center-skin / line-song / <scope>-emoji
  资源级: '<domain>-<kind>:<resourceId>'      # 例 chess-skin:neo / line-song:my-song / chess-emoji:default
  资产级: '<domain>-<kind>:<resourceId>:<asset>'   # 例 chess-skin:neo:wK / gomoku-skin:ink:black / line-song:my-song:audio

KV tags（kvV1.set tags=）:
  <domain>_<kind>:index  → ['<domain>-<kind>']   # 单条，覆盖整张索引
```

按线展开：

| 线 | domain-kind | resourceId | asset | KV tag |
|---|---|---|---|---|
| chess | `chess-skin` | skinId（数字/小写） | `wK / wQ / wR / wB / wN / wp / bK / bQ / bR / bB / bN / bp` | `chess-skin` |
| gomoku | `gomoku-skin` | skinId | `black / white / board` | `gomoku-skin` |
| game-center | `game-center-skin` | demo slug | `small / large` | `game-center-skin` |
| line | `line-song` | songId（kebab-case） | `audio / cover / chart` | `line-song` |
| emoji | `<scope>-emoji`（scope=common 或 gameId） | packId（`default` 或自命名） | `<emojiId>` | `<scope>-emoji` |

**设计动机**（全 5 条线通用）：
- 共同的 `<domain>-<kind>` 让 `GET /api/v1/kv/tags?groupId=190` 一眼能看出"我有多少种资源"
- `<domain>-<kind>:<id>` 让前端能 `GET /files?tags=chess-skin:3` 一次拉某资源全部资产（已可用于预览/批量换图 UI）
- `<domain>-<kind>:<id>:<asset>` 粒度最细，未来按资产增量更新直接定位 file

**一次性 retro-tag**：chess 历史 84 张图（旧 add_skin.py 未带 tags）通过 `scripts/retag_existing.py` 一键补打。其他 4 条线暂无历史包袱（建线时即带 tag）。

## 命名约定（与 `GameSkinSpec` 对齐）

每条线都派生自一个稳定 ID（gameId 或 domainId），所有 KV key / tag / 文件目录 / SharedPreferences key 都从该 ID 派生：

```
KV key:    <gameId>_<kind>:index          # chess_skin:index / gomoku_skin:index / line_song:index
                                       # 例外：emoji → emoji_<scope>:index、game-center → game-center_skin:index
File tag:  <gameId>-<kind>              # chess-skin / gomoku-skin / line-song
File key:  <gameId>/<id>/<asset>        # chess/neo/wK / line/my-song/audio / gomoku/ink/black
```

emoji 是唯一带 `<scope>` 的：scope=`common` 或 `gameId`（如 `emoji_chess:index`），tag 也是 `<scope>-emoji`（如 `chess-emoji`、`line-emoji`），允许同一 emoji id 在不同 game scope 下指向不同 file（game 覆盖 common，详见 `EmojiBundle.forGame`）。

## 管线总览

```
【ve 管理端 / fr 上传脚本】（任一条线）
  资源目录（N 张 webp/png/mp4/jpg…）
    │ scripts/add_<thing>.py <dir> <id> [--scope <scope>]
    ▼ POST /api/v1/files × N（登录）→ N 个 32-hex file_id
  file_id 映射（stdout JSON + 可存档）
    │ 拼 meta JSON（id/assets/{k: {fileId,…}}）
    │ 脚本自动：拉旧 index → 按 id 合并 → 全量写回
    ▼ POST /api/v1/kv  key=<domain>_<kind>:index  visibility=public  groupId=190
  KV public 生效

【客户端（已实现，零改动）】
  main() / 页面 initState
    ├─ 本地 hardcode 兜底（catalog 字段 const 写死）
    └─ unawaited(fetchAndMerge*())  ← KV 拉取覆盖/追加；失败静默回退
  渲染
    └─ 图按 file_id 走 /files/<id> 匿名下载 + 本地磁盘持久化
```

## 快速上手（已有图片目录时）

### A. 新增一套游戏皮肤（chess / gomoku / game-center）

```bash
# 0) 登录（脚本从 ~/.kvcli/config.json 读 token）
kvcli auth login

# 1) chess（默认）：12 张 webp，命名 00_white_king.webp 等
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/skins/neo neo

# 2) gomoku：3 张（black.png / white.png / board.png，允许 webp/jpg 互换）
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/skins/ink ink --game gomoku --name "水墨"

# 3) game-center 封面：2 张（small.webp + large.webp；skinId = demo slug）
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/covers/gomoku gomoku-lua --game game-center --name "五子棋（联机）"

# 4) 客户端重启 app → 新资源出现在列表（无需发版）
```

### B. 新增一套表情包（任意 scope）

```bash
# common 作用域：所有游戏都可见（与游戏无关的表情，如 thumbs-up）
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py D:/emojis/celebration celebration --scope common --name "庆祝"

# 特定游戏作用域（如 chess-emoji，只在 chess 房间显示）
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py D:/emojis/chess_only chess-faces --scope chess

# 重发已有 pack（覆盖：删除旧 emoji id 不再上传的 file）
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py D:/emojis/celebration celebration --scope common
```

### C. 发布游戏中心目录（新增/下线游戏）

```bash
# 改 lib/core/game_kit/game_center_catalog.dart 的 kGameCenterCatalog 后：
dart run tool/publish_game_center_index.dart
# 发布后 ve game-skin-admin ?tab=covers 即可看到新列表
```

### D. 一次性补打 chess 历史 tags

```bash
# 仅历史数据需要：旧版 add_skin.py 没发 tags，84 张图补 tag 让 facet 可见
python .claude/skills/game-skin-pipeline/scripts/retag_existing.py
```

### E. 把 line 曲库从 Supabase 迁过来

```bash
python .claude/skills/game-skin-pipeline/scripts/migrate_line_from_supabase.py --dry-run  # 预览
python .claude/skills/game-skin-pipeline/scripts/migrate_line_from_supabase.py           # 正式
```

## 通用故障排查入口

| 症状 | 排查 |
|---|---|
| 资源没出现在列表 | ① 匿名读验证：`curl 'http://47.110.80.47:8988/api/v1/kv/public/<key>?groupId=190'` 应返回 code 0；② value 是否合法 JSON array 且无重复 id（parseList 整批拒绝）；③ 客户端是否真重启（fetch 仅启动拉一次） |
| 列表有资源但显示空白 | ① file_id 是否 32-hex 且真实存在：`curl -I 'http://…/files/<id>'`（HEAD 404 是已知怪癖，用 GET/字节计数验证）；② 本地缓存目录是否半残：app 文档目录删掉重下 |
| 换了图但不更新 | KV index 是全量覆盖语义：重新 publish（version+1 + 新 fileId）；本地已缓存的旧图按资源目录持久化 —— **改图必须换新 id 或让用户清缓存** |
| upload 脚本 401 | `kvcli auth whoami` 检查登录；token 过期重登 |
| upload 404 | 用了错误路径（`/api/v1/upload`）——本 skill 脚本已用正确路径，检查是否被改动 |
| KV 写成功但匿名读 404 | 写入时 `visibility` 不是 `public`，或 `groupId` 不是 190 |
| emoji 发了但客户端不显示 | ① scope 是否正确（common vs game）；② emoji id 是否匹配 `^[a-z0-9][a-z0-9-_]{0,31}$`；③ 客户端日志里看 KV 读取是否 200 |

## 引用索引

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[extend-sop]] | 新增/更换资源、端到端 SOP、故障排查 | `references/extend-sop.md` |
| [[architecture]] | 理解加载链路、KV value schema、文件地图 | `references/architecture.md` |
| [[emoji-sop]] | 表情包特定：scope 合并、id 命名、pack meta 解析 | `references/emoji-sop.md` |