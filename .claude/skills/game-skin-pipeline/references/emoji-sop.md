# 子 ref C：表情包（emoji pack）端到端 SOP

> 从 [SKILL.md](../SKILL.md) 导航进入。本文是**表情包专用 SOP**：scope 合并机制、id 命名约束、两种 KV value 形态、与 GameSkin 体系的差异。
> 通用 SOP 见 [[extend-sop]] §6；架构细节见 [[architecture]] §2.5 / §3.5。

## 1. 两种 KV value 形态（共存）

表情包 KV value 是 JSON array，但**数组元素的形态有两种**（都在生产环境流通）：

### A) 管理后台扁平 open-set（ve emoji-pack-admin 现行）

```json
[
  { "id": "thumbs-up", "file": { "fileId": "<32-hex>", "fileName": "thumbs-up.webp", … } },
  { "id": "happy",     "file": { "fileId": "<32-hex>", "fileName": "happy.webp", … } },
  { "id": "...": }
]
```

- 每元素顶层就是单个 emoji（无 pack 嵌套）
- `EmojiPackMeta.parseList` 自动识别 → **合成一个 `id='default'` 的合成 pack**
- ve 后台默认产出此形态

### B) pack 嵌套数组（历史 / 自有工具）

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

- `emojis` 字段是 `id → FileRef` 映射（扁平）
- 多个 pack 可在同一 array（每个元素一个 pack）
- 历史或自有工具产出此形态

**两种形态混合不报错**（parseList 按"看首项"判断全局形态，但单元素 `_looksLikeFlatEmojiItem` 容错——即如果首项是扁平，整批按扁平解析；首项是嵌套，整批按嵌套解析）。

## 2. Scope 合并机制（game 覆盖 common）

```
EmojiBundle.forGame(gameId) 流程:
  scope = ['common', gameId]
  for s in scopes:
    readString('emoji_<s>:index')  // 匿名 GET /api/v1/kv/public/...
    if success: parse → list[EmojiPackMeta]
  id → FileRef 合并（后者覆盖前者）:
    for pack in packs:
      for (emojiId, fileRef) in pack.emojis:
        merged[emojiId] = fileRef    // 后到的覆盖先到的
  // → merged: id → FileRef，game scope 覆盖 common
```

**含义**：
- `emoji_common:index` 是全局表情（任何游戏都能用）
- `emoji_<gameId>:index` 是游戏专属表情（仅在该游戏的房间可见）
- 同 id 冲突 → 用 game 的 fileId 渲染

## 3. 与 GameSkin 体系的关键差异速览

| 项 | GameSkin | Emoji |
|---|---|---|
| scope 概念 | 单 gameId | 必带 scope（common 或 gameId） |
| 合并策略 | 同 gameId 内按 skinId 去重覆盖 | **跨 scope 合并**：common + game，game 覆盖 common |
| 形态 | 单一 JSON array of meta | 两种并存（flat open-set / pack 嵌套） |
| 兜底 | Layer 1 const catalog | 无 unicode 兜底（未发布的 emoji 不可见） |
| 本地缓存 | per skin 目录 + `.done` 标记 | per scope 目录 + `.emoji-index.json`（含 fileId 版本校验） |
| 渲染 | ImageProvider map（pieces） | FileImage 优先，回退 NetworkImage |

## 4. KV key 与 tag

| 项 | 值 |
|---|---|
| KV key | `emoji_<scope>:index`（scope = `common` 或 `gameId`） |
| groupId | 190 public |
| KV tag | `<scope>-emoji`（如 `common-emoji` / `chess-emoji` / `line-emoji`） |
| File key | `emoji/<scope>/<packId>/<emojiId>`（脚本默认；可省 packId 段） |
| File tag 三级 | `<scope>-emoji` / `<scope>-emoji:<packId>` / `<scope>-emoji:<packId>:<emojiId>` |

## 5. 命名约束

| 项 | 正则 / 约束 |
|---|---|
| scope | `^[a-z0-9][a-z0-9-_]{0,31}$`（建议 `common` 或 gameId） |
| packId | `^[a-z0-9][a-z0-9-]{0,31}$`（kebab-case；形态 A 固定 `default`） |
| emojiId | `^[a-z0-9][a-z0-9-_]{0,31}$`（允许下划线） |

**为什么 emoji id 允许下划线**（与 skinId 不同）：单个表情常有 `thumbs_up` / `heart_broken` 之类语义化 snake_case 名。

## 6. 端到端 SOP

### 6.1 准备

```bash
# 0) 登录
kvcli auth login

# 1) 准备 emoji 目录：每个表情一个文件，文件名 = emojiId + 扩展名
mkdir -p D:/emojis/celebration
# 文件示例：
#   D:/emojis/celebration/thumbs-up.webp
#   D:/emojis/celebration/happy.webp
#   D:/emojis/celebration/heart.webp
```

文件命名约定：`<filename>` 的 stem（去掉扩展名）即 emoji id。允许的扩展名：`.webp / .png / .jpg / .jpeg / .gif`。

### 6.2 上传 + 发布

```bash
# common 作用域
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py \
    D:/emojis/celebration celebration \
    --scope common --name "庆祝"

# 游戏作用域
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py \
    D:/emojis/chess_only chess-faces \
    --scope chess

# 同 pack 重发（覆盖：删除旧 emoji id 不再上传的 file）
python .claude/skills/game-skin-pipeline/scripts/add_emoji_pack.py \
    D:/emojis/celebration celebration --scope common
```

脚本行为：
1. 扫描目录，识别每个表情文件（`.<ext>` 扩展名按 webp/png/jpg/gif 顺序）
2. 逐文件 `POST /api/v1/files`（带 `key=emoji/<scope>/<packId>/<emojiId>` + 三级 tag）
3. 拼 pack meta `{id: packId, displayName, version, emojis: {id: FileRef}}`
4. 拉旧 `emoji_<scope>:index` → 按 packId 合并 → 校验 → 写回（`visibility=public`，`groupId=190`，`tags=[<scope>-emoji]`）
5. 匿名读验证
6. 同 packId 覆盖：best-effort DELETE 旧 emojis 中不再上传的 fileId

### 6.3 客户端验证

1. 重启 app（`EmojiBundle.forGame` 在每个房间 initState 拉）
2. 进入对应 scope 的房间（common 任意游戏；game scope 仅对应游戏）
3. 点表情按钮 → 新表情出现在面板 → 发送 → 房间飘字正常

## 7. 故障排查（emoji 专属）

| 症状 | 排查 |
|---|---|
| 房间内看不到新表情 | ① scope 是否匹配房间 gameId；② KV 读验证：`curl 'http://47.110.80.47:8988/api/v1/kv/public/emoji_<scope>:index?groupId=190'`；③ emoji id 是否匹配 `^[a-z0-9][a-z0-9-_]{0,31}$`（下划线 OK，连字符 OK） |
| 表情显示但发不出去 | ① emoji_id 参数是否与 KV value 里的 id 一致；② 协议层 EMOJI 命令格式（参 `lib/core/game_kit/emoji/emoji_script.dart`） |
| 表情飘字但图挂了 | ① `emoji_bundle.dart` 的 `_resolveCachedFileFor` 用 fileId 校验（.emoji-index.json 里若 fileId 不匹配则回退网络）；② 网络被屏蔽 |
| 同 pack 重发后旧 file 残留 | 脚本 §6.2 步骤 6 best-effort DELETE；失败也不会阻塞发布，可手动调 DELETE /files/<id> |
| scope=game 的 emoji 在 common 房间不显示 | 设计如此：game scope 仅在该游戏的房间可见 |

## 8. 与 ve 端 emoji-pack-admin 的协同

- ve 后台 `?tab=emoji` 编辑 → 客户端拉取 → 形态 A（flat open-set，合成 default pack）
- fr 端自有工具发 pack → 客户端拉取 → 形态 B（pack 嵌套）
- **同一 key 上**两种形态混存会让客户端首项决定整体解析模式（一旦首项定型，整批按该模式解析）。生产环境强烈建议：
  - 仅一种来源（如只用 ve 后台）保持形态一致
  - 自有工具发布前清空旧 KV 再发新（避免混形态）