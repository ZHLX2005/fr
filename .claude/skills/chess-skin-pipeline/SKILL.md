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
| 上传 12 张棋子图拿 file_id | 跑 `upload_pieces.sh` | `scripts/upload_pieces.sh` |
| 把 meta JSON 发布到 KV public | 跑 `publish_index.sh` | `scripts/publish_index.sh` |
| 理解皮肤系统架构（本地兜底 + KV 覆盖 + File 图 + 本地缓存） | [[architecture]] | `references/architecture.md` |
| 皮肤不生效 / 图 404 / KV 读不到 → 排查 | [[troubleshooting]]（extend-sop §5） | `references/extend-sop.md` §5 |

## 核心事实（后端能力，已实测）

| 能力 | 接口 | 鉴权 |
| --- | --- | --- |
| 棋子图上传 | `POST /api/v1/files`（multipart，field=`file`，可带 `key`/`accessLevel=public`） | **需登录** |
| 棋子图下载 | `GET /files/<fileId>` | **匿名 ✅** |
| KV 写入 | `POST /api/v1/kv`（`visibility=public`, `groupId=190`） | **需登录** |
| KV public 匿名读 | `GET /api/v1/kv/public/<key>?groupId=<gid>` | **匿名 ✅** |
| KV 标准读 | `GET /api/v1/kv/<key>` | 需登录 ❌（勿用） |
| KV share 访问 | `GET /api/v1/kv/share/<code>` | 需登录 ❌（勿用） |

> 🚨 **三个实测踩坑，勿重蹈**：
> 1. 上传路径是 `/api/v1/files`（multipart field 必须叫 `file`），**不是** `/api/v1/upload`（404）。
> 2. KV 匿名读**必须**走 `/api/v1/kv/public/<key>?groupId=N`（N≥1，用 190 shared 公共组）；标准 `/api/v1/kv/<key>` 匿名一律 401。
> 3. KV share（`/kv/share/:code`）在 MustAuth 组内，**不是**匿名通道。

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

# 1) 上传一套皮肤的 12 张棋子图（例如 D:/skins/neo/ 目录）
bash .claude/skills/chess-skin-pipeline/scripts/upload_pieces.sh D:/skins/neo neo

# 2) 按 stdout 输出拼 meta JSON（模板见 extend-sop §2），发布
bash .claude/skills/chess-skin-pipeline/scripts/publish_index.sh ./neo_meta.json

# 3) 客户端重启 app → 新皮肤出现在换肤列表（无需发版）
```

## 引用索引

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[extend-sop]] | 新增/更换皮肤、排查皮肤问题 | `references/extend-sop.md` |
| [[architecture]] | 理解加载链路与文件地图 | `references/architecture.md` |
