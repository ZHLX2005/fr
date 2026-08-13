# 小说阅读器后端对接调研

> 日期：2026-08-13
> 状态：调研文档，供决策参考；不包含实现计划
> 关联：Task 6 of `2026-08-13-fr-theme-desaturation-and-scrollbar`

## 0. 背景

原始问题：**小说阅读器是否可以对接后端以及存在的 server？**

后端实情：fr 项目对接的 GoFrame `dev_ctr_hello`（`http://47.110.80.47:8988`）已在跑，
但只暴露**通用 KV + 文件上传 + 工作区**三类能力；没有任何 book/novel/library 的领域端点，
`api_spec.json`（最近一次抓取 `2026-06-22-7225201`）内 `book|novel|library|reader`
关键字命中数 = 0。所以"对接后端"必须重新回答：**哪些数据上云、上云到哪一格、走哪个端点、
登录态要不要启用**。下文分章评估。

---

## 1. 现状盘点

### 1.1 存储表（全部位于客户端）

源码：`lib/core/novel_reader/novel_reader_storage.dart` + `novel_reader_constants.dart`：

| 数据 | 落点 | 关键 key/路径 |
|---|---|---|
| 书架目录 | SharedPreferences | `lab.novel_reader.library`（JSON 数组） |
| 当前选中书籍 | SharedPreferences | `lab.novel_reader.selected_book_id` |
| 每本书的页码进度 | SharedPreferences | `lab.novel_reader.last_page_index.<bookId>`（int） |
| 每本书的页内偏移 | SharedPreferences | `lab.novel_reader.last_page_offset.<bookId>`（int） |
| 字号 / 行高 / 主题 / 音量翻页 | SharedPreferences | `lab.novel_reader.font_size` / `.line_height` / `.theme` / `.volume_key_turn` |
| 书籍正文（TXT） | 应用文档目录文件 | `<appDocs>/novel_reader/<fileName>.txt`（`getApplicationDocumentsDirectory()` 子目录，类见 `NovelReaderStorage._getBooksDirectory`） |
| 内置书下载源 | 硬编码 URL | `https://kklrbynhqpwwhtfanqwt.supabase.co/storage/v1/.../sevenDay.txt`（见 `novel_reader_constants.dart:remoteUrl`） |

### 1.2 关键事实

- **正文拉取不经 `lib/api/`**。内置书的下载走 `package:http` 直发 `http.Request('GET', Uri.parse(remoteUrl))`
  （`novel_reader_storage.dart:165`）。这意味着：无 `AuthInterceptor`、无统一信封解析、
  无全局错误兜底、进度回调得自己攒。
- **`lib/core/novel_reader/` 对 `lib/api/` 零依赖**。grep 整目录无 `import '../../../api/...'`、
  无 `GoframeConfig`、无 `KvEndpoint`/`FileEndpoint` 的引用。
- **`lib/api/goframe/` 无对应 domain**。`lib/api/goframe/{ai,article,download,file,group,kv,room}/`
  七个模块，最接近的是 `file`（通用上传/下载元数据）和 `kv`（通用键值），都没有 book/novel
  概念，也没有"书架"或"阅读进度"的领域建模。
- **整包备份已"顺带"覆盖本模块的元数据**：`lib/core/storage/sync/cloud_storage_sync.dart`
  把 `StorageExporter.buildDumpText()` 序列化的文本写到单个 KV key
  (`fr_storage_backup:<name>`)。`StorageExporter` 遍历 `SharedPreferences.getInstance()`
  所有 key，所以 `lab.novel_reader.*` 全部被顺带备份。但**正文文件（`novel_reader/*.txt`）不导出**
  （导出器只扫 Hive boxes + prefs + 笔记 TOML），这是当前备份的盲区。
- **`api_spec.json` 无 book 契约**。抓取最近一次 `2026-06-22-7225201`，正则 `book|novel|library|reader`
  命中 0。

### 1.3 现状结论

阅读器目前是**纯本地单端应用**：所有数据落客户端，无任何写后端动作。"对接后端"严格来说不是
"接入已有接口"，而是**借通用积木搭出阅读器专用的云端表示**。这意味着后端无须新增端点，但
客户端要新建 service/契约层。

---

## 2. 两条路线对比

阅读器数据天然分三层：**正文（最大、最重）、书架元数据（轻量、用户私有）、阅读进度
（极轻、高频写）**。这两条路线对正文态度截然不同。

### 2.1 路线 A：多端同步（**正文留本地**）

书架 + 进度 + 偏好设置 跨设备共享；正文仍在本地文件。换机或新设备登入后，先看到空书架 +
云端进度；正文需要时按需下载（首次靠内置书走 Supabase；导入的书由"上次在本机导入"承担
现实约束）。

### 2.2 路线 B：云端书库（**正文也上云**）

书架 + 进度 + 偏好设置 跨设备共享；正文走 `FileEndpoint.upload` 上传，server 持有一份。
换机或新设备登入后看到完整书架；正文按需下载（`downloadUrl` 已在 `FileUploadResult`
 里给出）。

### 2.3 四维度对比

| 维度 | 路线 A：多端同步 | 路线 B：云端书库 |
|---|---|---|
| **工作量（客户端代码）** | 1 个 service + 6 个 KV key + 迁移钩子。改动 < 300 行 | 1 个 service + 上传/下载/分块 + 失败重试 + 文件指纹去重。改动 600–1000 行，且需要处理大文件上传（`FileEndpoint.upload` 当前 body 里塞 `file_bytes` List，正文可能 MB 级，请求体膨胀） |
| **后端工作量** | 0（用现有 KV + groupId 即可） | 0（同上）。但**当前 `/api/v1/upload` 没看到分块/断点续传端点**，MB 级单请求是隐忧 |
| **是否强依赖登录态** | **强**。多端同步没有稳定用户身份等于没有 owner → KV 跨设备串台。必须先把 `TokenManager` 从"待用"切到"启用" | **更强**。正文上传要绑定 owner，否则隐私与计费都失控。登录态必须是硬门槛 |
| **离线可用性** | **完全保留**。正文本来就在本地，离线照常读；进度写入可走"先本地 + 后台上云"队列，离线不影响翻页 | **部分保留**。已下载的正文本地有缓存；新书 / 换机后无网即空白。需要本地预下载机制 |
| **流量成本（用户视角）** | 仅元数据（几 KB），几乎免费 | 正文上传/下载各一次（按需缓存可降）；导入 N 本 = N 次 MB 级上行 |
| **隐私/合规** | 进度/偏好上云（弱敏感），正文不出本机 | 用户的私人 TXT 进云（强敏感）。涉及阅读历史 → 隐私面更广 |
| **数据丢失风险** | 本机丢 = 正文丢，但用户感知是"换机要重新导入"，符合当前预期 | 本机丢 = 正文丢，但服务端还在；理论可恢复 — 但前提是用户当初同意上传 |
| **实现风险** | 低。复用现成 KV、迁移钩子照搬 `cloud_storage_sync.dart` 模式即可 | 高。需要解决：上传大文件策略、断点续传、hash 去重、`importedAt` 时钟漂移、删除两边同步 |

### 2.4 结论性观察

路线 A 解决的是**真实痛点**（换机重读 / 多端进度同步），工作量最小、隐私面最窄、与现有离线优先
策略完美契合；路线 B 解决的痛点是"换机后书还在"，但当前读者已经把"导入到本机"当作既定行为
（`importBookFromPath` 是公开 API），贸然改成云端书库会改变产品定义。

> 路线 A 在三个核心维度（工作量、隐私、离线）都优于路线 B；在"换机后书还在"这一项劣于 B，
> 但该项当前**没有用户明确抱怨过**。

---

## 3. 数据映射方案（按路线 A，路线 B 仅做差异说明）

### 3.1 总体策略

- **正文文件**：**不上云**，继续走 `NovelReaderStorage.getBookFile()` / `readLocalText()`。
  已下载的内置书从 Supabase 拉；用户导入的 TXT 仍走 `importBookFromPath`。
- **书架 + 进度 + 偏好**：走 `KvEndpoint`，用 `groupId` 作用域（personal group 即"我的"）。
- **owner 标识**：登录后的 `userId`（来自 `UserAuthService.userInfo()` 的 `data.id`）。

### 3.2 KV key 命名（草案）

```
fr_novel_reader:library                  # string(JSON array of NovelBookEntry)
fr_novel_reader:selected_book_id        # string
fr_novel_reader:progress:<bookId>       # int (page index)
fr_novel_reader:progress_offset:<bookId># int
fr_novel_reader:font_size               # int
fr_novel_reader:line_height             # int
fr_novel_reader:theme                   # string
fr_novel_reader:volume_key_turn         # bool (string "true"/"false")
```

> 命名逻辑：模块前缀 `fr_novel_reader:`（与 `fr_storage_backup:` 一致风格），便于以后 `kv.list`
> 过滤；进度按 `bookId` 切 key 而非打包进单条 JSON，**写冲突粒度更小**（同一本书两端同时翻页
> 是常见场景）。

### 3.3 JSON schema 草案

#### 3.3.1 书架（`fr_novel_reader:library`）

> 结构与 `NovelBookEntry.toJson()`（`novel_reader_storage.dart:40-49`）完全对齐，无 schema 风险：

```json
[
  {
    "id": "builtin_seven_day",
    "title": "Seven Day",
    "fileName": "sevenDay.txt",
    "source": "builtIn",
    "remoteUrl": "https://kklrbynhqpwwhtfanqwt.supabase.co/.../sevenDay.txt",
    "importedAt": null
  },
  {
    "id": "9f1c…",
    "title": "My Imported Book",
    "fileName": "my_imported_book_9f1c….txt",
    "source": "imported",
    "remoteUrl": null,
    "importedAt": 1755000000000
  }
]
```

**云端 vs 本地差异**（端上要做 schema 兼容）：
- 云端多了 `fileId`（路线 B 用，路线 A 留 `null`）。
- 云端用 `updatedAt`（int，毫秒）做后写优先（last-write-wins）冲突仲裁；本地不需要。
- 客户端 `fromJson` 接受缺字段，向前兼容旧 dump。

#### 3.3.2 进度（每本书一个 KV key）

```
fr_novel_reader:progress:<bookId>        → "123"           (int as string in JSON)
fr_novel_reader:progress_offset:<bookId> → "4567"          (int as string in JSON)
```

> KV value 是 string。进度的"页码"和"偏移"用 string-encoded int，避免后端 JSON number 精度
> 问题（js 大整数掉精度）。

### 3.4 groupId 作用域

- `KvEndpoint.set/get/delete/list` 均支持可选 `groupId`（`kv_endpoint.dart:27-71`）。
- 推荐：所有 `fr_novel_reader:*` key 都带 `groupId: <personal-group-id>`。personal group
  通过 `GroupEndpoint.list()` 拿到 `KvGroup.id` + `myRole='owner'`，过滤 `myRole == 'owner'
  && name == 'personal'`（或与后端约定一个 sentinel）。**这保证 user-A 的进度不会污染 user-B**。
- 上传时一律 `kv.set(..., groupId: gid)`；读取时 `kv.get(..., groupId: gid)` / `kv.list(..., groupId: gid)`。

### 3.5 路线 B 差异说明

- 多了 `fr_novel_reader:library` 中每个 `NovelBookEntry.fileId` 字段（路线 B 用，路线 A 不用）。
- 正文走 `FileEndpoint.upload(fileName: 'sevenDay.txt' / '...txt', bytes: utf8.encode(text))`，
  返回 `FileUploadResult.id` 写入 `fileId`；下载走 `FileEndpoint.metadata(id)` 拿
  `downloadUrl` 后直接 HTTP GET（同当前内置书下载路径）。
- `importBookFromPath` 之后要追加 `kv.set(library)` 把 `fileId` 同步上去。
- `removeBook` 要追加 `FileEndpoint.delete(fileId)`。

---

## 4. 登录态方案

### 4.1 当前状态（已验证）

- `UserAuthService`（`lib/api/user/user_auth_service.dart`）已实现 `sendCode` / `login` /
  `register` / `userInfo`，登录成功把 JWT 写入 `SharedPrefsTokenStorage`（key `api_access_token`）。
- `TokenManager`（`lib/api/token/token_manager.dart`）持有内存 token + `_hydrate()` 启动时读
  持久化。注释明确说"已接入但处于**待用**状态"。
- `AuthInterceptor`（`lib/api/interceptors/auth_interceptor.dart`）自动从 `TokenManager` 读
  token 注入 `Authorization: Bearer …` 头；遇 401 调 `tryRefresh()` — **当前实现是 stub，
  返回 false**（`token_manager.dart:46-49`）。
- **GoFrame 端 auth 是可选**：`AuthInterceptor` 注释"无 token 时自动跳过"。这是为何
  `lib/lab/demos/storage_analyze_demo.dart` 的云同步 tab 已经是登录闸样式，但现有调用全可
  匿名跑。
- **`UserAuthService._baseUrl` 硬编码** `http://47.110.80.47:8988/api/v1`（不走
  `GoframeConfig.baseUrl`）。这点与 `cloud_storage_sync` 设计文档（2026-08-02）描述一致。

### 4.2 是否启用

路线 A 要求登录态**作为多端同步的前置条件**；路线 B 同理甚至更强。

启用 = 切换 `AuthInterceptor` 拦截 + 注入 header。当前**实际已自动启用** — 任何走
`ApiClient` 的请求都会带上 token（如果有）。所以"启用"实际语义是：

1. **登录入口**：阅读器 settings 加"账号"页（含注册/登录/已登录信息），使用
   `UserAuthService.login/register/userInfo`，复用已有卡片逻辑（`storage_analyze_demo` 的云同步
   tab 已是范本）。
2. **未登录降级**：未登录时云同步相关按钮置灰 + tooltip「请先登录」；本地功能全部照常。
3. **退出登录**：`TokenManager.clear()` + 清掉所有 `fr_novel_reader:*` KV（个人数据不能留在
   KV 里给下一个人）。需要写"清理 KV"方法（用 `kv.list(groupId: gid)` 列出前缀 → `kv.delete`）。
4. **token 过期**：`AuthInterceptor` 401 触发 `tryRefresh()` → 当前是 stub，会失败 → 用户
   看到"登录已失效"提示。生产级需要后端给 refresh 端点 + `UserAuthService.refresh()` 实现。

### 4.3 启用代价 / 影响面

| 项 | 评估 |
|---|---|
| 后端 | **0** 改动。auth 是可选的。 |
| 客户端 UI | 加登录闸 + 登录/退出流程（参考 `storage_analyze_demo` 云同步 tab 的 200 行代码量） |
| 客户端架构 | `TokenManager`/`AuthInterceptor` 不动；只需加一个阅读器专属的 `AuthGate` widget |
| 现有功能 | **无破坏**。未登录走原路径；登录后才出现云端写。 |
| 风险 | `tryRefresh` 是 stub → 长会话需要重新登录。当前用户体量小可接受。 |
| 测试 | 已有 `CloudStorageSync` 单测范本可借鉴（mock `KvEndpoint`） |

### 4.4 是否硬门槛？

- 路线 A 推荐：**登录态作为多端同步的开关，未登录时云同步功能隐藏**，本地阅读不阻断。
- 路线 B 推荐：**登录态作为整个阅读器模块的硬门槛**（未登录不允许用阅读器）。这会改变
  当前默认 — 慎重。

---

## 5. 迁移路径

### 5.1 第一次启用云同步

目标用户：**当前已经用过阅读器、书架里已有书 + 进度的用户**。

```
启动阅读器 → 检测到 KV 里无 fr_novel_reader:library
            → 但本地 prefs 有 lab.novel_reader.library
            → 弹一次性迁移提示：「把书架/进度同步到云端？」
            → 确认 → 把现有 prefs 全量镜像到 KV（key 重映射见 §3.2）
            → 写入完成，本地 prefs 保留为 cache（避免网络挂时丢数据）
```

### 5.2 同步策略

**离线优先**：所有读写都先落本地，再异步上云。本地 = 权威副本（single source of truth），
云端 = 跨设备镜像。

```text
用户翻页 → setLastPageIndex(local) → 触发 debounce 1s → kv.set(progress:<id>)
                                              ↓
                                          失败？→ 进重试队列；不弹错（弱同步）
                                              ↓
                                          成功？→ 清队列
```

进度 key 单独存（不打包进 library JSON）的好处：每次翻页只写一个 KV key，**写延迟低、
冲突粒度小**。`library` / `font_size` / `theme` 这类低频写，每次写整条 JSON 也无所谓。

### 5.3 冲突处理

两端同时打开同一本书翻页的常见情形：

```
device-A 读到 p.100,  offset 200 → fr_novel_reader:progress:X = 100
device-B 读到 p.105,  offset 80  → fr_novel_reader:progress:X = 105
```

方案：**Last-Write-Wins，按 timestamp**。

- 每次写 KV 时附带"本地写入时间戳"（key 上塞时间戳或者 value 末尾追加 `ts` 字段）：
  ```
  fr_novel_reader:progress:X   →   "105|1755000001234"
  ```
  不需要单独 schema：value 解析时按 `|` 切分。
- 拉取时：如果云端 ts > 本地 ts → 用云端覆盖本地；否则保留本地 + 后台上写。
- 接受"晚写覆盖早写"的语义。优点：零用户干预；缺点：两端各自翻过的页会被"最新"覆盖。
  对阅读器这个场景**完全可接受**（不存在"合并页码"这种语义）。

### 5.4 删除/退出

- 用户在 device-A 删除某本 → 本地 `removeBook` + `kv.set(library)` 重写（不带该本）。
- 用户在 device-A 退出登录 → `TokenManager.clear()` + 列出 `fr_novel_reader:*` 全部删除
  （避免数据泄露给下个登入者）。本地 prefs 保留（用户的本地体验不破坏）。
- 用户**永久删除云端所有数据**（GDPR 风）：在 settings 加"删除我的云端数据"按钮，
  走上述清理流程 + 二次确认。

### 5.5 路线 B 的迁移差异

- 第一次启用：除了元数据，**正文也要上传**。进度：批量上传每本书 → 进度反馈 → 完成后写
  library.json。
- 删除：device-A 删除 → `kv.set(library)` + `FileEndpoint.delete(fileId)`。
- 离线优先同样保留。

---

## 6. 推荐

**推荐路线 A：先做"多端同步"，正文留本地。**

理由：
1. **工作量最小**。约 300 行新增代码（含 service + UI 登录闸 + 迁移钩子），复用现有
   `KvEndpoint` / `GroupEndpoint` / `UserAuthService` / `AuthInterceptor` 即可，**后端 0 改动**。
2. **零隐私争议**。用户的私人 TXT 不出本机；进度/偏好是弱敏感数据。
3. **离线优先天然成立**。本机永远是 source of truth，云端是镜像 — 与当前产品行为完全一致。
4. **解决真实痛点**。"换机后阅读进度/字号/主题还在"是用户多端使用的高频诉求；
   "换机后我导入的书还在"是低频需求，且通过"在我的常用设备上重新导入"可被合理接受。
5. **风险面窄**。失败模式全是"云端写失败" — 本地不受影响。登录态作为可选开关，
   现有用户**不会**因为升级而功能回退。
6. **可演进**。路线 A 落地后再评估路线 B 的需求强度；如果未来真有"换机后我导入的书也要
   在"的强诉求，那时 `FileEndpoint.upload` + 正文 schema 可以作为路线 A 的**增量扩展**
   （library 项加 `fileId` 字段，向后兼容）。

### 6.1 不推荐路线 B 的核心理由

- 当前 `FileEndpoint.upload` 是把 `file_bytes` 塞到 JSON body（`file_endpoint.dart:18`）。
  一本 5MB 的 TXT = 5MB JSON 请求体；如服务端没专门调过 gunicorn/GoFrame body limit，
  **极可能直接 413/断连**。除非先做"分块上传"或"走 multipart"重构，否则路线 B 不可靠。
- 即使解决了上传，下载路径仍要落 HTTP GET `downloadUrl`，与内置书 Supabase 下载两条路径并行，
  维护面翻倍。

### 6.2 路线 A 的里程碑（建议下一步）

1. 在 `lib/core/novel_reader/` 下新建 `novel_reader_sync.dart`，提供 `Future<void>
   pushLibrary()` / `pushProgress(bookId)` / `Future<void> pullAll()`，依赖 `KvEndpoint` +
   `GroupEndpoint`。
2. 在 `NovelReaderStorage` 的关键写入路径（`setLastPageIndex`、`setLastPageOffset`、
   `_saveLibrary`）后调 `syncService.onLocalChanged(...)`，内部 debounce + 队列。
3. 启动时跑一次性迁移（§5.1），幂等。
4. settings 页加"账号"入口 + "云同步"开关（关掉就不写 KV）。

---

## 7. 待用户拍板的开放问题

下列问题直接影响路线 A 的实现细节，需要明确决策才能开工：

1. **登录态的硬性程度**：未登录时
   - (a) 阅读器照常本地用，云同步隐藏 — **推荐**；
   - (b) 阅读器完全不可用，强制登录；
   - (c) 弹窗引导但不阻断。
2. **冲突 UX**：last-write-wins 够不够？要不要做"检测到冲突时弹窗让用户选保留哪端"？
3. **数据保留策略**：用户退出登录后，云端 `fr_novel_reader:*` 是
   - (a) 立即删除（隐私优先）— **推荐**；
   - (b) 保留 30 天后清（容错优先）。
4. **多组（group）支持**：阅读器数据走 personal group 还是某个特定业务 group？
   取决于后端是否有"个人空间"概念；当前 `GroupEndpoint.list()` 列**所有**用户的 group，
   需要约定一个 marker（`name == 'personal'`？或者后端加 `is_personal` 字段？）。
5. **KV 限额**：路线 A 写频率 = 每翻页 1 次 × 每页 debounce 1s ≈ 1 write/s/用户。
   KV 后端是否有 rate limit？没有的话无所谓，有的话要加客户端合并窗口。
6. **正文路线 B 的去向**：现在不做，但 6 个月后是否要做？如果"会做"，建议路线 A 的
   schema 直接给 `NovelBookEntry` 预留 `fileId: String?` 字段，迁移成本更低。

---

## 8. 参考资料

- 源码：`lib/core/novel_reader/novel_reader_storage.dart`、`novel_reader_constants.dart`
- 源码：`lib/api/goframe/{kv,file,group}/*.dart`
- 源码：`lib/api/{user,token,interceptors}/*.dart`
- 源码：`lib/core/storage/sync/cloud_storage_sync.dart`、`lib/core/storage/export/storage_exporter.dart`
- 历史设计：`docs/superpowers/specs/2026-08-02-cloud-storage-sync-design.md`
- 后端契约：`api_spec.json` 最近抓取 `2026-06-22-7225201`（grep `book|novel|library|reader` 命中 0）
- 调研任务：`.superpowers/sdd/2026-08-13-fr-theme-desaturation-and-scrollbar/task-6-brief.md`