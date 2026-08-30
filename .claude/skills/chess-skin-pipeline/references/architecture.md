# 子 ref A：皮肤系统架构（加载链路 + 文件地图）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文讲**客户端怎么加载皮肤**（混合策略三层）与**代码在哪**。
> 上传/发布 SOP 见 [[extend-sop]]。

## 1. 三层混合加载（v 当前实现）

```
Layer 1  本地 hardcode（零网络兜底）
  kChessSkinsCatalog（lib/core/chess/skins/chess_skin_meta.dart）
  7 套皮肤 meta + 84 个 file_id 全部 const 写死
  main() 启动期 ChessSkinBundle.registerHardcoded() 装入

Layer 2  KV public 覆盖（免发版增量）
  main() 启动期 unawaited(fetchAndMergeSkins())
  （lib/core/chess/skins/chess_skin_meta_sync.dart）
  流程：匿名 GET /api/v1/kv/public/chess_skin:index?groupId=190
    → ChessSkinMeta.parseList(json)（重复 id/非法 id 直接 FormatException 整批拒绝）
    → ChessSkinBundle.registerRemoteSkins(metas)
       · 同 id → 覆盖本地版本
       · 新 id → 追加
       · 绝不删除本地、绝不触碰 'default'
  任何失败（网络/超时/格式）→ 静默保留 Layer 1，零回归

Layer 3  图片本地化（离线渲染）
  ChessSkinLocalizer（lib/core/chess/skins/chess_skin_localizer.dart）
  首次使用某皮肤时：12 张图按 file_id 匿名 GET /files/<id>
    → 写入 <app documents>/chess_skins/<skinId>/*.webp + .done 标记
    → LocalChessSkin 用 FileImage 渲染（之后零网络）
  **缓存优先（Fix "已下载仍转圈"）**：
    · ensureLocal(meta)：isCached 命中 → fromCache 直接返回（零网络、不删缓存）；
      未命中 → download 全量补齐。设置页点选 / 重试 / initState 预取都走它。
    · download(meta)：无条件清目录重下（KV 换图等强刷场景才用）。
    · demo 的 _downloadSkin 先 isCached 探测 → 命中则跳过 loading 态（不转圈）。
  下载中：loading icon；失败：错误 + 重试（HTTP 5s 超时，绝不无限转圈）
  失败清理：任一张失败 → 清空该皮肤目录（不留半缓存）
```

**优先级**：KV meta（L2）> 本地 meta（L1）；图片本地文件（L3）> 网络拉取。

## 2. 文件地图

| 路径 | 职责 |
| --- | --- |
| `lib/core/chess/skins/chess_skin_meta.dart` | `ChessSkinMeta`/`FileRef` 模型 + `parseList` + **`kChessSkinsCatalog`（本地 7 套 const）** |
| `lib/core/chess/skins/chess_skin.dart` | `ChessSkin` 接口 + `ChessSkinBundle`（registerHardcoded / registerRemoteSkins / byId） |
| `lib/core/chess/skins/chess_skin_meta_sync.dart` | `fetchAndMergeSkins()` KV 覆盖入口 |
| `lib/core/chess/skills/public_kv_reader.dart` → 实为 `skins/public_kv_reader.dart` | 匿名 KV public 读（裸 http，无鉴权头，5s 超时，失败 null） |
| `lib/core/chess/skins/remote_chess_skin.dart` | `RemoteChessSkin`（meta+resolver → ImageProvider map） |
| `lib/core/chess/skins/local_chess_skin.dart` | `LocalChessSkin`（本地文件 FileImage 渲染） |
| `lib/core/chess/skins/chess_skin_localizer.dart` | 下载器（isCached/fromCache/download，dir 可注入测试） |
| `lib/core/chess/skins/file_resolver.dart` | `PublicFileResolver`：`url(fileId) = $base/files/$fileId` |
| `lib/core/chess/skins/chess_skin_prefs.dart` | 选中皮肤 id 持久化（SharedPreferences key `chess_skin_id`） |
| `lib/core/chess/skins/chess_skin_settings_page.dart` | 全屏换肤设置页（左列表右实时预览 + 自定义棋盘色） |
| `tool/upload_chess_skins/chess_skins_file_ids.json` | 现役 84 file_id 存档（chess/2/{1..7} 来源） |

## 3. meta JSON Schema（KV `chess_skin:index` 的 value）

KV value = **JSON array**，每元素一套皮肤：

```json
[
  {
    "id": "neo",
    "displayName": "霓虹",
    "version": 1,
    "colorStyle": "vivid",
    "createdAt": "2026-08-30T00:00:00Z",
    "updatedAt": "2026-08-30T00:00:00Z",
    "pieces": {
      "wK": { "fileId": "<32-hex>", "fileName": "00_white_king.webp", "sizeBytes": 10396, "contentType": "image/webp" },
      "wQ": { … }, "wR": { … }, "wB": { … }, "wN": { … }, "wp": { … },
      "bK": { … }, "bQ": { … }, "bR": { … }, "bB": { … }, "bN": { … }, "bp": { … }
    },
    "boardBackground": null
  }
]
```

**硬约束**：
- `pieces` **必须严格 12 个 key**：`wK wQ wR wB wN wp bK bQ bR bB bN bp` —— 缺一则 `meta.isComplete == false`，UI 回退 unicode。
- `id` 必须匹配 `^[a-z0-9][a-z0-9-]{0,31}$`；array 内**不可重复**（重复 → parseList 整批 FormatException → 客户端回退本地全部，一颗老鼠屎坏一锅粥，发布前务必校验）。
- `fileId` 是 File API 返回的 32-hex；图片仍可匿名下载（File 下载与 KV 无关，不随 KV TTL 过期）。
- 只需发布**增量/变更**的皮肤？不 —— index 是**全量 array**：publish_index.sh 会先拉旧 index 合并去重再写回，所以手工编辑时也请保持全量语义。

## 4. 与棋盘颜色（BoardPalette）的关系

- 皮肤（本管线）= **棋子图片**（+可选棋盘底图 boardBackground）。
- 棋盘**格子颜色**走 `context.chessColors`（主题）或用户自定义 `BoardPalette`（优先级最高），与本管线正交。
- 若 skin 带 `boardBackground`，则作为棋盘底图渲染在两色格之下。
