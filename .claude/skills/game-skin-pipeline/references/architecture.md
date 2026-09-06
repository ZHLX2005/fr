# 子 ref A：游戏资源加载架构（5 条线统一视图）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文讲**客户端怎么加载资源**（混合策略三层）与**代码在哪**。
> 上传/发布 SOP 见 [[extend-sop]]；表情包特定见 [[emoji-sop]]。

## 1. 三层混合加载（全 5 条线同构）

```
Layer 1  本地 hardcode（零网络兜底）
  · chess:    kChessSkinsCatalog（lib/core/chess/skins/chess_skin_meta.dart）
              7 套皮肤 meta + 84 个 file_id 全部 const 写死
  · gomoku:   GomokuSkinBundle 内置 fallback（无 KV 时不显示自定义皮肤）
  · game-center: 程序化封面（GameArtwork，零 KV 也可工作）
  · line:     内置空列表，KV 缺失则歌曲列表为空
  · emoji:    空 bundle（EmojiBundle.empty()），无 unicode 兜底
  main() / 页面 initState 期：registerHardcoded() 装入

Layer 2  KV public 覆盖（免发版增量）
  · chess:    fetchAndMergeSkins() （lib/core/chess/skins/chess_skin_meta_sync.dart）
  · gomoku:   fetchAndMergeGomokuSkins()
  · game-center: fetchAndMergeGameCenterSkins()
  · line:     ChartRepository.loadIndex() 内部走 PublicKvReader
  · emoji:    EmojiBundle.forGame(gameId) 内部走 PublicKvReader 两次（common + game）

  通用流程（每条线）：
    匿名 GET /api/v1/kv/public/<line>_<kind>:index?groupId=190
      → parseList(json)（重复 id/非法 id 直接 FormatException 整批拒绝）
      → registerRemoteSkins(metas) / registerRemotePacks(metas)
         · 同 id → 覆盖本地版本
         · 新 id → 追加
         · 绝不删除本地、绝不触碰 'default'
  任何失败（网络/超时/格式）→ 静默保留 Layer 1，零回归

Layer 3  图片本地化（离线渲染）
  · chess:    ChessSkinLocalizer（lib/core/chess/skins/chess_skin_localizer.dart）
              <app documents>/chess_skins/<skinId>/*.webp + .done
  · gomoku:   同上体系（<app documents>/gomoku_skins/<skinId>/*）
  · game-center: GameCenterLocalizer（<app documents>/game-center_skins/<slug>/*）
  · line:     LineCacheManager（charts/audio/covers 三目录，按 fileId 命名）
  · emoji:    EmojiBundle 自管（<app documents>/emojis/common/<id>.<ext> + .emoji-index.json）

  通用流程：
    首次使用某资源：N 张图按 file_id 匿名 GET /files/<id>
      → 写入 <app documents>/<dir>/<id>/* + .done/.emoji-index.json
      → LocalXxxSkin 用 FileImage 渲染（之后零网络）
  缓存优先：
    · ensureLocal(meta)：isCached 命中 → fromCache 直接返回（零网络、不删缓存）；
      未命中 → download 全量补齐。设置页点选 / 重试 / initState 预取都走它。
    · download(meta)：无条件清目录重下（KV 换图等强刷场景才用）。
  下载中：loading icon；失败：错误 + 重试（HTTP 5s 超时，绝不无限转圈）
  失败清理：任一张失败 → 清空该资源目录（不留半缓存）
```

**优先级**：KV meta（L2）> 本地 meta（L1）；图片本地文件（L3）> 网络拉取。

## 2. 文件地图（按线展开）

### 2.1 chess（历史最完整，含三层混合）

| 路径 | 职责 |
|---|---|
| `lib/core/chess/skins/chess_skin_meta.dart` | `ChessSkinMeta` / `FileRef` 模型 + `parseList` + **`kChessSkinsCatalog`（本地 7 套 const）** |
| `lib/core/chess/skins/chess_skin.dart` | `ChessSkin` 接口 + `ChessSkinBundle` |
| `lib/core/chess/skins/chess_skin_meta_sync.dart` | `fetchAndMergeSkins()` KV 覆盖入口（兼容 wrapper） |
| `lib/core/chess/skins/public_kv_reader.dart` | `export '../../game_kit/skin/public_kv_reader.dart'`（已抽离到 game_kit） |
| `lib/core/chess/skins/remote_chess_skin.dart` | `RemoteChessSkin`（meta+resolver → ImageProvider map） |
| `lib/core/chess/skins/local_chess_skin.dart` | `LocalChessSkin`（本地文件 FileImage 渲染） |
| `lib/core/chess/skins/chess_skin_localizer.dart` | 下载器（isCached/fromCache/download，dir 可注入测试） |
| `lib/core/chess/skins/file_resolver.dart` | `PublicFileResolver`：`url(fileId) = $base/files/$fileId` |
| `lib/core/chess/skins/chess_skin_prefs.dart` | 选中皮肤 id 持久化（SharedPreferences key `chess_skin_id`） |
| `lib/core/chess/skins/chess_skin_settings_page.dart` | 全屏换肤设置页（左列表右实时预览 + 自定义棋盘色） |
| `tool/upload_chess_skins/chess_skins_file_ids.json` | 现役 84 file_id 存档（chess/2/{1..7} 来源） |

### 2.2 gomoku（五子棋皮肤）

| 路径 | 职责 |
|---|---|
| `lib/core/gomoku/skins/gomoku_skin.dart` | `GomokuSkin` / `GomokuSkinBundle`（与 chess 同构） |
| `lib/core/gomoku/skins/gomoku_skin_meta.dart` | `GomokuSkinMeta` 模型（asset keys：`black/white/board`） |
| `lib/core/gomoku/skins/gomoku_skin_meta_sync.dart` | `fetchAndMergeGomokuSkins()` KV 覆盖入口 |
| `lib/core/gomoku/skins/` | localizer / remote / local（与 chess 同构） |

### 2.3 game-center（游戏中心封面）

| 路径 | 职责 |
|---|---|
| `lib/core/game_kit/skin/game_center_skin_spec.dart` | `kGameCenterSkinSpec` + `gameCenterSkinBundle` + `fetchAndMergeGameCenterSkins()` + `gameCenterCoverOf(slug, assetKey)` |
| `lib/core/game_kit/game_center_catalog.dart` | `kGameCenterCatalog` 目录常量 + `gameCenterCatalogJson()`（发 KV 用） |
| `tool/publish_game_center_index.dart` | `dart run` 一行发布目录到 `game-center_catalog:index` |

### 2.4 line（音游曲库）

| 路径 | 职责 |
|---|---|
| `lib/core/line/io/line_song_spec.dart` | `kLineSongAssetKeys` / `kDefaultLineSongBaseUrl` / `kLineSongKvIndexKey` / `lineSongKvReader()` / `lineSongFileResolver()` |
| `lib/core/line/io/chart_repository.dart` | `ChartRepository.loadIndex()` / `loadSong()` / `precacheSong()` 等静态方法，内部走 PublicKvReader + /files/<id> + LineCacheManager |
| `lib/core/line/cache/line_cache_manager.dart` | 三目录持久化（charts/audio/covers）+ 下载进度回调 |
| `lib/core/line/domain/song_data.dart` / `song_record.dart` | 运行时 + KV meta 数据模型 |

### 2.5 emoji（表情包）

| 路径 | 职责 |
|---|---|
| `lib/core/game_kit/emoji/emoji_pack_meta.dart` | `EmojiPackMeta` 模型 + `parseList`（自动识别 flat open-set vs pack 嵌套）+ `kvIndexKeyForScope` + `kvTagForScope` |
| `lib/core/game_kit/emoji/emoji_bundle.dart` | `EmojiBundle.forGame(gameId)`：拉 common + game 两个 scope，game 覆盖 common；`prefetchToCache` 预取 |
| `lib/core/game_kit/emoji/emoji_overlay.dart` | 房间内表情飘字渲染 |
| `lib/core/game_kit/emoji/emoji_panel.dart` | 表情选择面板 UI |
| `lib/core/game_kit/emoji/emoji_script.dart` | 表情脚本执行（lua 状态机交互） |

### 2.6 通用层（5 条线共用）

| 路径 | 职责 |
|---|---|
| `lib/core/game_kit/skin/public_kv_reader.dart` | `PublicKvReader`（裸 http，匿名，best-effort，5s 超时，never throws） |
| `lib/core/game_kit/skin/file_resolver.dart` | `PublicFileResolver`（拼 file URL）+ `PublicKvReader` 的 baseUrl 默认值 |
| `lib/core/game_kit/skin/game_skin_meta.dart` | `FileRef` 模型（被 emoji 复用）+ `GameSkinMeta` 模型 |
| `lib/core/game_kit/skin/game_skin_spec.dart` | `GameSkinSpec` + chess/gomoku 常量 + `kGroupId = 190` |
| `lib/core/game_kit/skin/game_skin_bundle.dart` | `GameSkinBundle`（chess/gomoku 用）+ `GameSkin` 接口 + `GameDefaultSkin` |
| `lib/core/game_kit/skin/game_skin_meta_sync.dart` | `fetchAndMergeSkinsFor(bundle, ...)` 通用 fetch 入口 |

## 3. KV value Schema（5 条线 + 1 条目录）

每条线 KV value 都是 **JSON array**（每元素一条资源）；emoji 的 value 元素是 `EmojiPackMeta`，其余是各游戏的 meta 对象。

### 3.1 chess (`chess_skin:index`)

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
- `pieces` **必须严格 12 个 key**：`wK wQ wR wB wN wp bK bQ bR bB bN bp` —— 缺一则 `meta.isComplete == false`，UI 回退 unicode
- `id` 必须匹配 `^[a-z0-9][a-z0-9-]{0,31}$`；array 内**不可重复**（重复 → parseList 整批 FormatException → 客户端回退本地全部，一颗老鼠屎坏一锅粥，发布前务必校验）
- `fileId` 是 File API 返回的 32-hex；图片仍可匿名下载

### 3.2 gomoku (`gomoku_skin:index`)

```json
[
  {
    "id": "ink",
    "displayName": "水墨",
    "version": 1,
    "pieces": {
      "black": { "fileId": "<32-hex>", "fileName": "black.webp", "sizeBytes": …, "contentType": "image/webp" },
      "white": { "fileId": "<32-hex>", "fileName": "white.webp", … },
      "board": { "fileId": "<32-hex>", "fileName": "board.webp", … }   // 可选
    }
  }
]
```

### 3.3 game-center (`game-center_skin:index`)

```json
[
  {
    "id": "gomoku-lua",
    "displayName": "五子棋（联机）",
    "version": 1,
    "pieces": {
      "small": { "fileId": "<32-hex>", "fileName": "small.webp", … },
      "large": { "fileId": "<32-hex>", "fileName": "large.webp", … }
    }
  }
]
```

**约束**：`id` = fr demo slug（与 `kGameMeta` / `GameDefinition.slug` 字符级一致）。

### 3.4 line (`line_song:index`)

```json
[
  {
    "id": "my-song",
    "displayName": "My Song",
    "artist": "Anonymous",
    "intro": "...",
    "bpm": 120,
    "durationMs": 180000,
    "difficulty": 1,
    "dropDurationMs": 2500,
    "version": 1,
    "assets": {
      "audio": { "fileId": "<32-hex>", "fileName": "song.mp3", "sizeBytes": …, "contentType": "audio/mpeg" },
      "cover": { "fileId": "<32-hex>", "fileName": "cover.webp", … },
      "chart": { "fileId": "<32-hex>", "fileName": "chart.json", "contentType": "application/json" }
    }
  }
]
```

**约束**：`id` 必须匹配 `^[a-z0-9][a-z0-9-]{0,31}$`（kebab-case）；`chart` JSON 不进 KV body，谱面 notes 一律走 File。

### 3.5 emoji (`emoji_<scope>:index`，scope=common 或 gameId)

两种形态并存（详见 [[emoji-sop]] §1）：

**A) 管理后台扁平 open-set（ve emoji-pack-admin 现行格式）**：
```json
[
  { "id": "thumbs-up", "file": { "fileId": "<32-hex>", "fileName": "thumbs-up.webp", … } },
  { "id": "happy",     "file": { "fileId": "<32-hex>", "fileName": "happy.webp", … } },
  { "id": "...": }
]
```

**B) pack 嵌套数组（历史/自有工具）**：
```json
[
  {
    "id": "celebration",
    "displayName": "庆祝",
    "author": "...",
    "description": "...",
    "version": 1,
    "emojis": {
      "thumbs-up": { "fileId": "<32-hex>", "fileName": "thumbs-up.webp", … },
      "happy":     { "fileId": "<32-hex>", "fileName": "happy.webp", … }
    }
  }
]
```

`EmojiPackMeta.parseList` 自动识别形态 A → 合成一个 `id=default` 的合成 pack；形态 B → 原样解析。

### 3.6 game-center_catalog (`game-center_catalog:index`)

不是资源目录，是**游戏列表元数据**（与 `<game>_skin:index` 同 KV 体系但不发 File）：

```json
[
  {
    "slug": "gomoku-lua",
    "title": "五子棋（联机）",
    "description": "Gomoku 互联网双人对战 · Lua 服务端权威棋谱",
    "mode": "联机双人",
    "categories": ["multiplayer", "board"],
    "isOnline": true
  }
]
```

**事实源**：`lib/core/game_kit/game_center_catalog.dart` 的 `kGameCenterCatalog`；修改后跑 `tool/publish_game_center_index.dart`。

## 4. KV value 校验规则（全 5 条线通用）

发布脚本自动校验（已实测）：
- `code == 0`（后端业务成功）
- value 是合法 JSON array
- 每元素 `id` 匹配 `^[a-z0-9][a-z0-9-]{0,31}$`
- array 内 id 唯一（去重）
- 每元素 asset key 全集匹配（chess 12 / gomoku 3 / game-center 2 / line 3；emoji 不强校验 asset，全集由 pack 自描述）
- 每元素 `fileId` 是 32-hex

任何一条不满足 → `parseList` 在客户端抛 `FormatException` → 整批拒绝 → 客户端静默回退本地 Layer 1（**一颗老鼠屎坏一锅粥**，发布前务必校验）。

## 5. 与棋盘颜色 / 主题的关系

- 皮肤（本管线）= **资源图片**（棋子 / 落子贴图 / 封面 / 表情 / 音频 / 谱面）。
- 主题色（`context.chessColors` / `context.colors`）= 主题系统，独立于本管线。
- 棋盘**格子颜色**在 chess 走 `BoardPalette`（用户自定义），与本管线正交；若皮肤带 `boardBackground`，则作为棋盘底图渲染在两色格之下。

## 6. ve 端使用方

| 管线 | ve 端组件 |
|---|---|
| chess | apps/showcase/src/components/ChessSkinAdmin.vue（dev+prod 都可见，按 `KvItem.myRole === 'owner'` 决定是否展示修改 UI） |
| gomoku | gomoku Skin Admin（同形态，按 game-skin-admin 路由分发） |
| game-center | apps/showcase/src/components/GameCoverAdmin.vue（`?tab=covers`） |
| line | line Song Admin（同形态） |
| emoji | apps/showcase/src/components/EmojiPackAdmin.vue（`?tab=emoji`） |
| game-center_catalog | 不需要 ve 组件（仅读取 `kGameCenterCatalog`，由 fr dart 脚本发布） |