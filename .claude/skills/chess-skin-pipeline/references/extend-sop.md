# 子 ref B：新增/更换皮肤端到端 SOP + 排查

> 从 [SKILL.md](../SKILL.md) 导航进入。本文是**操作手册**：从一张图片目录到客户端免发版生效，以及常见故障排查。
> 架构细节见 [[architecture]]。

## 0. 前置条件

1. 后端可达：`http://47.110.80.47:8988`（如换了服务器，同步改 SKILL.md 与 `kDefaultChessSkinBaseUrl`）。
2. 已登录 kvcli（脚本从 `~/.kvcli/config.json` 读 token）：
   ```bash
   kvcli auth login    # 交互登录；whoami 验证
   ```
3. 皮肤图片目录就绪（见 §1 规范）。

## 1. 图片资源规范

- **12 张 webp**，透明底，命名固定（与 piece key 对应）：

| 文件名 | piece key | | 文件名 | piece key |
| --- | --- | --- | --- | --- |
| `00_white_king.webp` | wK | | `06_black_king.webp` | bK |
| `01_white_queen.webp` | wQ | | `07_black_queen.webp` | bQ |
| `02_white_rook.webp` | wR | | `08_black_rook.webp` | bR |
| `03_white_bishop.webp` | wB | | `09_black_bishop.webp` | bB |
| `04_white_knight.webp` | wN | | `10_black_knight.webp` | bN |
| `05_white_pawn.webp` | wp | | `11_black_pawn.webp` | bp |

- 目录里允许有其它文件（如 `_preview_grid.webp`、`00_full_transparent.webp`）——上传脚本只认 12 个固定名，其余自动跳过。
- 单张建议 ≤ 100KB（webp 透明底，现役最大 ~10KB/张）。
- 可选棋盘底图：`board.png|webp`（1:1 正方形）——v 当前 7 套均未使用。

## 2. 端到端流程

### 2.1 上传图片拿 file_id

```bash
bash .claude/skills/chess-skin-pipeline/scripts/upload_pieces.sh <图片目录> <skinId>
# 例：
bash .claude/skills/chess-skin-pipeline/scripts/upload_pieces.sh D:/skins/neo neo
```

- 逐张 `POST /api/v1/files`（multipart field=`file`，`accessLevel=public`，`key=chess/<skinId>/<pieceKey>`）。
- 输出：`{ "<skinId>": { "wK": "<fileId>", … 12 项 } }` 到 stdout；**建议重定向存档**：
  ```bash
  bash …/upload_pieces.sh D:/skins/neo neo | tee tool/upload_chess_skins/neo_file_ids.json
  ```
- 任何一张失败 → 脚本非零退出并列出失败项；**重跑即可**（File 每次上传生成新 file_id，旧文件留着无害；把新输出整份替换旧映射即可）。

### 2.2 拼 meta JSON

用 2.1 的 file_id 输出拼一个单皮肤 meta 文件（`neo_meta.json`）：

```json
{
  "id": "neo",
  "displayName": "霓虹",
  "version": 1,
  "colorStyle": "vivid",
  "createdAt": "2026-08-30T00:00:00Z",
  "updatedAt": "2026-08-30T00:00:00Z",
  "pieces": {
    "wK": { "fileId": "<stdout 里的 32-hex>", "fileName": "00_white_king.webp", "sizeBytes": 10396, "contentType": "image/webp" },
    … 共 12 项 …
  }
}
```

> `sizeBytes`/`contentType` 影响不大（缓存键参考），如实填即可；`contentType` 用 `image/webp`。
> 更换版本时：`version +1`、`updatedAt` 刷新、`pieces` 换新 fileId —— 同 id 发布即覆盖。

### 2.3 合并发布到 KV public

```bash
bash .claude/skills/chess-skin-pipeline/scripts/publish_index.sh neo_meta.json
```

脚本自动：拉旧 `chess_skin:index`（登录态标准 GET）→ 按 id 合并去重（新覆盖旧）→ 校验（12 key / id 唯一 / 32-hex）→ `POST /api/v1/kv` 写回（`visibility=public`，`groupId=190`）→ 匿名读回验证。

### 2.4 客户端验证

1. 重启 app（`fetchAndMergeSkins` 仅启动时拉）。
2. 国际象棋在线 → 调色盘 → 新皮肤应出现在列表，预览正常出图。
3. （首次会触发图片本地化下载，稍等 loading。）

## 3. 现役皮肤来源（历史）

| skinId | 来源目录 | 备注 |
| --- | --- | --- |
| 1–7 | `D:\DevProjects\my\test\image\chess\2\{1..7}\` | 84 file_id 存档于 `tool/upload_chess_skins/chess_skins_file_ids.json`；`2/bR` 曾服务端丢失，已重传为 `d3f95f6e…`（5416B） |

## 4. 后端参考（为何这么调）

- 上传 controller：`dev_ctr_hello/internal/controller/file/v1/file.go`（`path:"/files"` + multipart `file` 字段）—— 客户端 `FileEndpoint.uploadByKey` 走的 `/api/v1/upload` 是**旧契约，路由未挂载（404）**，勿用。
- KV public 匿名读：`GET /api/v1/kv/public/:key?groupId=N`（N≥1）。`groupId=190` = "shared" 公共组。
- KV share（`/kv/share/:code`）在 MustAuth 组内，**不是**匿名通道，皮肤管线勿用。

## 5. 故障排查

| 症状 | 排查 |
| --- | --- |
| 新皮肤没出现在列表 | ① 匿名读验证：`curl 'http://47.110.80.47:8988/api/v1/kv/public/chess_skin:index?groupId=190'` 应返回 code 0；② value 是否合法 JSON array 且无重复 id（parseList 整批拒绝）；③ 客户端是否真重启（fetch 仅启动拉一次） |
| 列表有皮肤但棋子空白/unicode | ① file_id 是否 32-hex 且真实存在：`curl -I 'http://…/files/<id>'`（GET 200 才算在；HEAD 404 是已知怪癖，用 GET/字节计数验证）；② 该皮肤目录本地缓存是否半残：app 文档目录 `chess_skins/<skinId>/` 删掉重下 |
| 换了图但不更新 | KV index 是全量覆盖语义：重新 publish（version+1 + 新 fileId）；本地已缓存的旧图按 `<skinId>/` 目录持久化 —— **改图必须换新 skinId 或让用户清缓存**（同 id 覆盖只影响未下载过的新设备） |
| upload 脚本 401 | `kvcli auth whoami` 检查登录；token 过期重登 |
| upload 404 | 用了错误路径（`/api/v1/upload`）——本 skill 脚本已用正确路径，检查是否被改动 |
| KV 写成功但匿名读 404 | 写入时 `visibility` 不是 `public`，或 `groupId` 不是 190 |
| 下载 loading 永久转 | 已修复（5s 超时）；若复现检查 `ChessSkinLocalizer` 是否仍带 timeout |
