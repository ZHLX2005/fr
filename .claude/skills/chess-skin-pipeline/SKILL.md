---
name: chess-skin-pipeline
description: 国际象棋皮肤管线 —— 从图片资源到客户端生效的完整链路（File API 上传棋子图 → KV public 发布皮肤索引 → 客户端混合加载）。当要"新增/更换一套棋子皮肤""上传棋子图片""更新 chess_skin:index""排查皮肤不生效/图挂了/发版免发版"时触发。含可执行上传脚本与端到端 SOP。
---

# Chess 皮肤管线 — 图片上传 → KV 发布 → 客户端免发版生效

> 一句话：**新皮肤 = 12 张 webp 走 File API 上传拿 file_id → 拼 meta JSON → 写进 KV public（`chess_skin:index`，groupId=190）→ 客户端下次启动自动生效，无需发版。**

## 何时读哪个 ref / 用哪个脚本

| 场景 | 读/用 | 路径 |
| --- | --- | --- |
| **新增一套皮肤（端到端）** | [[extend-sop]] 全流程走一遍 | `references/extend-sop.md` |
| 上传 12 张棋子图拿 file_id | 跑 `add_skin.py` | `scripts/add_skin.py` |
| 把 meta JSON 发布到 KV public | 跑 `add_skin.py`（含合并发布） | `scripts/add_skin.py` |
| **一次性给已上传文件补 tag** | 跑 `retag_existing.py` | `scripts/retag_existing.py` |
| 理解皮肤系统架构（本地兜底 + KV 覆盖 + File 图 + 本地缓存） | [[architecture]] | `references/architecture.md` |
| 皮肤不生效 / 图 404 / KV 读不到 → 排查 | [[troubleshooting]]（extend-sop §5） | `references/extend-sop.md` §5 |

## 核心事实（后端能力，已实测）

| 能力 | 接口 | 鉴权 |
| --- | --- | --- |
| 棋子图上传 | `POST /api/v1/files`（multipart，`file` 字段 + `key`/`accessLevel=public` + `tags[]`） | **需登录** |
| 棋子图下载 | `GET /files/<fileId>` | **匿名 ✅** |
| 棋子图补 tag | `PATCH /api/v1/files/<fileId>` body=`{tags: [...], groupId: N}`（replace 语义） | **需登录** |
| KV 写入 | `POST /api/v1/kv`（`visibility=public`, `groupId=190`, `tags=[]` 可选） | **需登录** |
| KV public 匿名读 | `GET /api/v1/kv/public/<key>?groupId=<gid>` | **匿名 ✅** |
| KV 标准读 | `GET /api/v1/kv/<key>` | 需登录 ❌（勿用） |
| KV share 访问 | `GET /api/v1/kv/share/<code>` | 需登录 ❌（勿用） |
| KV tag facet | `GET /api/v1/kv/tags?groupId=<gid>` → `{tag, count}[]` | **需登录** |

> 🚨 **四个实测踩坑，勿重蹈**：
> 1. 上传路径是 `/api/v1/files`（multipart field 必须叫 `file`），**不是** `/api/v1/upload`（404）。
> 2. KV 匿名读**必须**走 `/api/v1/kv/public/<key>?groupId=N`（N≥1，用 190 shared 公共组）；标准 `/api/v1/kv/<key>` 匿名一律 401。
> 3. KV share（`/kv/share/:code`）在 MustAuth 组内，**不是**匿名通道，皮肤管线勿用。
> 4. PATCH /files 的 `tags` 是 **replace 语义**（空数组 = 清空）；不要把整组 tags 误传成单个 tag 字符串。

## Tag Schema（2026-09-01 起）

文件与 KV 在后端 tag 维度对齐，前端/管理工具按 tag 维度查询：

```
File tags（multipart tags[]=）:
  必带:   'chess-skin'
  皮肤级:  'chess-skin:<id>'           # 例 chess-skin:3
  棋子级:  'chess-skin:<id>:<pieceKey>' # 例 chess-skin:3:wK

KV tags（kvV1.set tags=）:
  chess_skin:index  → ['chess-skin']
```

**为什么是这套**：
- KV/file 一致的 `chess-skin` 让 `GET /api/v1/kv/tags?groupId=190` 一眼能看到"我有多少皮肤相关条目"
- `chess-skin:<id>` 让前端能 `GET /files?tags=chess-skin:3` 一次拉某皮肤 12 张图（已可用于预览/批量换图 UI）
- `chess-skin:<id>:<pieceKey>` 粒度最细，未来按棋子增量更新直接定位 file

**一次性 retro-tag**：已上传的 84 张图（旧 add_skin.py 未带 tags）通过 `scripts/retag_existing.py` 一键补打，运行后 `GET /api/v1/kv/tags` 应能看到 `chess-skin` facet。

## 管线总览

```
【一次性/每次新皮肤】
  皮肤目录（12 张 webp，命名 00_white_king … 11_black_pawn）
    │ scripts/upload_pieces.sh <dir> <skinId>
    ▼ POST /api/v1/files × 12（登录）→ 84/N 个 32-hex file_id
  file_id 映射（stdout JSON + 可存 tool/upload_chess_skins/）
    │ 拼 meta JSON（id/displayName/pieces{key:{fileId,…}}）
    │ scripts/publish_index.sh <meta.json>（合并已有 index）
    ▼ POST /api/v1/kv  key=chess_skin:index  visibility=public  groupId=190
  KV public 生效

【客户端（已实现，零改动）】
  main() 启动
    ├─ ChessSkinBundle.registerHardcoded()   ← 本地 7 套兜底（零网络）
    └─ unawaited(fetchAndMergeSkins())        ← KV 拉取覆盖/追加；失败静默回退
  对局/预览
    └─ 图按 file_id 走 /files/<id> 匿名下载 + 本地磁盘持久化（ChessSkinLocalizer）
```

## 快速上手（已有图片目录时）

```bash
# 0) 登录（脚本从 ~/.kvcli/config.json 读 token）
kvcli auth login

# 1) 端到端：上传 12 张棋子图 + 发布 KV（包含 tags）
python .claude/skills/chess-skin-pipeline/scripts/add_skin.py D:/skins/neo neo

# 2) （一次性）已上传的 84 张图补 tag —— 后续新皮肤无需再跑
python .claude/skills/chess-skin-pipeline/scripts/retag_existing.py

# 3) 客户端重启 app → 新皮肤出现在换肤列表（无需发版）
```

## 引用索引

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[extend-sop]] | 新增/更换皮肤、排查皮肤问题 | `references/extend-sop.md` |
| [[architecture]] | 理解加载链路与文件地图 | `references/architecture.md` |
