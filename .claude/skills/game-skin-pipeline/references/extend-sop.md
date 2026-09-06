# 子 ref B：游戏资源端到端 SOP + 故障排查

> 从 [SKILL.md](../SKILL.md) 导航进入。本文是**操作手册**：每条线的端到端 SOP（图片目录 → 客户端免发版生效），以及常见故障排查。
> 架构细节见 [[architecture]]；表情包特定见 [[emoji-sop]]。

## 0. 前置条件

1. 后端可达：`http://47.110.80.47:8988`（如换了服务器，同步改 SKILL.md 与各 `kDefaultXxxBaseUrl` 常量）。
2. 已登录 kvcli（脚本从 `~/.kvcli/config.json` 读 token）：
   ```bash
   kvcli auth login    # 交互登录；whoami 验证
   ```
3. 资源目录就绪（每条线规范见对应 §）。

---

## 1. 通用步骤（5 条线同构）

所有 5 条线都走同一脚本骨架 `add_<thing>.py <dir> <id> [...]`：

1. **上传资产** → 逐文件 `POST /api/v1/files`（multipart，`accessLevel=public`，`key=<gameId>/<id>/<assetKey>`，`tags[]` 三级 tag）
2. **拼 meta JSON** → 上一步 stdout 的 `{id: {asset: fileId}}` 映射 + 元数据（displayName/version/...）
3. **合并发布** → 登录态 GET `<domain>_<kind>:index`（旧）→ 按 id 合并去重 → `POST /api/v1/kv` 写回（`visibility=public`，`groupId=190`，`tags=[<common>]`）
4. **匿名读验证** → `GET /api/v1/kv/public/<key>?groupId=190` 应 code 0，array 长度 ≥ 期望
5. **同 id 覆盖时** → best-effort DELETE 旧 fileId（防 File 存储冗余）
6. **客户端验证** → 重启 app → 新资源出现

每条线的差异仅在：
- 资产文件命名/数量
- meta JSON 的字段（如 chess 的 `pieces` vs line 的 `assets`）
- KV key / tag 前缀 / file key 前缀

---

## 2. chess 端到端

### 2.1 图片资源规范

- **12 张 webp**，透明底，命名固定（与 piece key 对应）：

| 文件名 | piece key | | 文件名 | piece key |
| --- | --- | --- | --- | --- |
| `00_white_king.webp` | wK | | `06_black_king.webp` | bK |
| `01_white_queen.webp` | wQ | | `07_black_queen.webp` | bQ |
| `02_white_rook.webp` | wR | | `08_black_rook.webp` | bR |
| `03_white_bishop.webp` | wB | | `09_black_bishop.webp` | bB |
| `04_white_knight.webp` | wN | | `10_black_knight.webp` | bN |
| `05_white_pawn.webp` | wp | | `11_black_pawn.webp` | bp |

- 目录里允许有其它文件（如 `_preview_grid.webp`）——上传脚本只认 12 个固定名，其余自动跳过。
- 单张建议 ≤ 100KB（webp 透明底，现役最大 ~10KB/张）。
- 可选棋盘底图：`board.png|webp`（1:1 正方形）——v 当前 7 套均未使用。

### 2.2 端到端

```bash
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/skins/neo neo
# 可选：--name "霓虹" 自定义 displayName
```

脚本自动：上传 12 张 → 拉旧 `chess_skin:index` → 合并去重（新覆盖旧）→ 校验 → `POST /api/v1/kv` 写回（`visibility=public`，`groupId=190`，`tags=['chess-skin']`）→ 匿名读回验证 → 同 id 覆盖时 best-effort 删除旧 fileId。

任何一张失败 → 脚本非零退出并列出失败项；**重跑即可**（File 每次上传生成新 file_id，旧文件留着无害；把新输出整份替换旧映射即可）。

### 2.3 一次性 retro-tag（仅历史数据需要）

旧版 add_skin.py 没发 tags；如需为已上传的 84 张图补 tag，运行：

```bash
python .claude/skills/game-skin-pipeline/scripts/retag_existing.py
```

脚本读 `tool/upload_chess_skins/chess_skins_file_ids.json`、PATCH 每个 file、最后把 KV `chess_skin:index` 重写带上 `tags=['chess-skin']`。支持 `--dry-run` 先预览。**只跑一次就够了**，后续新上传由新版 add_skin.py 自动带 tag。

### 2.4 拼 meta JSON（如手动调整）

用 §2.2 的 file_id 输出拼一个单皮肤 meta 文件：

```json
{
  "id": "neo",
  "displayName": "霓虹",
  "version": 1,
  "colorStyle": "vivid",
  "createdAt": "2026-08-30T00:00:00Z",
  "updatedAt": "2026-08-30T00:00:00Z",
  "pieces": {
    "wK": { "fileId": "<32-hex>", "fileName": "00_white_king.webp", "sizeBytes": 10396, "contentType": "image/webp" },
    … 共 12 项 …
  }
}
```

> `sizeBytes`/`contentType` 影响不大（缓存键参考），如实填即可；`contentType` 用 `image/webp`。
> 更换版本时：`version +1`、`updatedAt` 刷新、`pieces` 换新 fileId —— 同 id 发布即覆盖。

### 2.5 客户端验证

1. 重启 app（`fetchAndMergeSkins` 仅启动时拉）。
2. 国际象棋在线 → 调色盘 → 新皮肤应出现在列表，预览正常出图。
3. （首次会触发图片本地化下载，稍等 loading。）

---

## 3. gomoku 端到端

### 3.1 图片资源规范

3 张图（建议 webp，允许 png/jpg 互换）：

| 文件名 | asset key |
| --- | --- |
| `black.png` | `black`（黑子） |
| `white.png` | `white`（白子） |
| `board.png` | `board`（棋盘底图，可选） |

`board` 是可选的；缺失时 `BoardColorStrategy.background` 走程序化背景。

### 3.2 端到端

```bash
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/skins/ink ink --game gomoku --name "水墨"
```

脚本自动：上传 3 张（或 2 张，无 board）→ 拉旧 `gomoku_skin:index` → 合并 → 写回（`tags=['gomoku-skin']`）→ 验证 → 清理孤儿。

客户端验证：进五子棋对局 → 调色盘 → 新皮肤出现。

---

## 4. game-center 端到端（封面）

### 4.1 图片资源规范

每款游戏 2 张图：

| assetKey | 用途 | 建议尺寸 |
| --- | --- | --- |
| `small` | 游戏中心网格卡封面 | 1.2:1（如 512×432） |
| `large` | 收藏轮播大卡封面 | 16:9（如 960×540） |

文件名固定 `small.webp` + `large.webp`（允许 png/jpg 互换）。

**skinId = fr demo slug**（如 `gomoku-lua`、`game-2048`），与 `kGameMeta` / `GameDefinition.slug` 字符级一致。

### 4.2 端到端

```bash
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/covers/gomoku gomoku-lua --game game-center --name "五子棋（联机）"
```

发布后重启 app 进游戏中心即可看到新封面；换图只需重传同 slug（version+1）。

### 4.3 游戏中心目录（game-center_catalog）

ve 的「游戏封面」tab **游戏列表来自 fr 发布的 KV 目录**，不手维护：

- KV key：`game-center_catalog:index`（groupId 190）；tag：`game-center-catalog`；value = JSON array（每项 slug/title/description/mode/categories/isOnline）
- 事实源：`lib/core/game_kit/game_center_catalog.dart` 的 `kGameCenterCatalog`（slug 必须与 `DemoPage.slug`、`kGameMeta` 一致；`GameCenterPage.initState` 有 debug 断言防漂移）
- **新增/下线游戏**：改 `kGameCenterCatalog`（+ 对应 demo 注册 / kGameMeta）后重发即可，ve 侧零改动

**发布目录**（已登录 kvcli）：

```bash
dart run tool/publish_game_center_index.dart
# 可选：--base <url> --group <n>（默认 http://47.110.80.47:8988 / 190）
```

发布后 ve game-skin-admin `?tab=covers` 即可看到新列表。

---

## 5. line 端到端（音游曲库）

### 5.1 资源规范

每首歌 3 个资产：

| asset | 文件类型 | 说明 |
| --- | --- | --- |
| `audio` | mp3 / m4a | 音频本体 |
| `cover` | webp / png | 封面 |
| `chart` | JSON | 谱面（不进 KV body，**必须走 File**） |

文件名按 fileId 自动命名（不要求固定名）；`songId` 必须匹配 `^[a-z0-9][a-z0-9-]{0,31}$`（kebab-case）。

### 5.2 上传单首歌

```bash
python .claude/skills/game-skin-pipeline/scripts/add_skin.py D:/songs/my-song my-song --game line
# 脚本期望 D:/songs/my-song/ 下有 audio.mp3 + cover.webp + chart.json
```

> 当前 `add_skin.py` 主要面向 skin/cover 类型（图片 + 固定命名）。line 的端到端 SOP **推荐用 migrate 脚本**（见 §5.3）或写类似工具；单首手动上传可参考 `migrate_line_from_supabase.py` 的 `migrate_one()` 思路直接调后端 API。

### 5.3 从 Supabase 迁移（一次性）

```bash
# 预览（不上传）
python .claude/skills/game-skin-pipeline/scripts/migrate_line_from_supabase.py --dry-run

# 正式迁移
python .claude/skills/game-skin-pipeline/scripts/migrate_line_from_supabase.py
# 可选：--limit 1 --base http://host:port --group 190
```

同 id 覆盖会 best-effort 删除旧 fileId。客户端进游戏中心 →「线」选歌即可。

---

## 6. emoji 端到端（表情包）

详细 SOP 见 [[emoji-sop]]。快速入口：

```bash
# common 作用域（全局）
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py D:/emojis/celebration celebration --scope common --name "庆祝"

# 游戏作用域（如 chess）
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py D:/emojis/chess_only chess-faces --scope chess

# 重发覆盖
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py D:/emojis/celebration celebration --scope common
```

文件命名约定见 [[emoji-sop]] §3。客户端验证：进对应游戏的房间 → 点表情按钮 → 新表情出现。

---

## 7. 通用故障排查

| 症状 | 排查 |
|---|---|
| 资源没出现在列表 | ① 匿名读验证：`curl 'http://47.110.80.47:8988/api/v1/kv/public/<key>?groupId=190'` 应返回 code 0；② value 是否合法 JSON array 且无重复 id（parseList 整批拒绝）；③ 客户端是否真重启（fetch 仅启动拉一次） |
| 列表有资源但显示空白 | ① file_id 是否 32-hex 且真实存在：`curl -I 'http://…/files/<id>'`（HEAD 404 是已知怪癖，用 GET/字节计数验证）；② 本地缓存目录是否半残：app 文档目录删掉重下 |
| 换了图但不更新 | KV index 是全量覆盖语义：重新 publish（version+1 + 新 fileId）；本地已缓存的旧图按资源目录持久化 —— **改图必须换新 id 或让用户清缓存**（同 id 覆盖只影响未下载过的新设备） |
| upload 脚本 401 | `kvcli auth whoami` 检查登录；token 过期重登 |
| upload 404 | 用了错误路径（`/api/v1/upload`）——本 skill 脚本已用正确路径，检查是否被改动 |
| KV 写成功但匿名读 404 | 写入时 `visibility` 不是 `public`，或 `groupId` 不是 190 |
| 下载 loading 永久转 | 已修复（5s 超时）；若复现检查 `<Resource>Localizer` 是否仍带 timeout |
| 已下载到本地但点选仍 loading 转圈 | 根因：上层 `_downloadXxx` 不查缓存，会先删目录重下。已修复 —— 上层现在**缓存优先**（`isCached` 命中 → `fromCache` 直接加载）。若复现：① 确认走的是 `ensureLocal`/`isCached` 路径而非直接 `download()`；② 检查 `<documents>/<dir>/<id>/` 是否被误删 |
| emoji 发了但客户端不显示 | ① scope 是否正确（common vs game）；② emoji id 是否匹配 `^[a-z0-9][a-z0-9-_]{0,31}$`；③ 客户端日志里看 KV 读取是否 200 |
| chess 客户端本地 catalog 与 KV index 漂移 | `lib/core/chess/skins/chess_skin_meta.dart` 的 `kChessSkinsCatalog` 改后未重发 KV。修复：发布 KV 后保证客户端 Layer 1/2 一致 |

## 8. 后端参考（为何这么调）

- 上传 controller：`dev_ctr_hello/internal/controller/file/v1/file.go`（`path:"/files"` + multipart `file` 字段）—— 客户端 `FileEndpoint.uploadByKey` 走的 `/api/v1/upload` 是**旧契约，路由未挂载（404）**，勿用。
- KV public 匿名读：`GET /api/v1/kv/public/:key?groupId=N`（N≥1）。`groupId=190` = "shared" 公共组。
- KV share（`/kv/share/:code`）在 MustAuth 组内，**不是**匿名通道，本管线勿用。
- KV index 全量覆盖语义：publish 脚本**先拉旧 → 合并 → 全量写回**；不要尝试只发增量（会导致历史数据丢失）。