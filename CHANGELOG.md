# Changelog

本文件记录项目的用户可感知变更。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 简化而来：
按日期倒序分组，模块前缀与 git commit scope 一致（`remotetype` / `ui` / `lab` / `auth` / `theme` …），`!` 标记破坏性变更。

**维护约定**：每完成一次功能 / 修复并 commit 后，在本文件最上方新增或合并到当日小节；只记 feat / fix / refactor 中影响行为或体验的条目，docs / chore / skill 内部工具变更不记。更早的历史用 `git log` 查阅。

---

## 2026-10-14

### 构建（build）

- **feat** 微豆子（weidouzi）双 app 构建链条：`build-apk-v2.yml` 新增 `app` 维度（`weidouzi` 选项），同一份代码产出可与小豆子并存安装的第二 app——独立签名（新 secret `WEIDOUZI_KEYSTORE_BASE64`，openssl 生成 PKCS12，alias `weidouzi`，与小豆子 `KEYSTORE_BASE64` 互不影响）、独立包名 `io.github.xiaodouzi.fr.wdz`、桌面名与小组件 label 切「微豆子」、应用内文案（profile 页 / 专注首页欢迎语 / 分享提示 / 录音权限指引 / 任务切换器标题）全部跟随变体。微豆子裁剪：无「语音合成」Tab、不支持自动下载（启动钩子 + 隐藏宿主 + 设置卡三处关闭）；检查更新 / 浏览器下载 / 内部下载保留，更新源指向独立 key `wdz_latest_apk`（避免下到小豆子包无法覆盖安装）。实现 = 构建期注入（gradle 属性 `appVariant` + `--dart-define=APP_VARIANT`），源码默认行为零改动；小豆子链路（v1/v2 workflow、上传 key、artifact 名）原样。新增 `lib/core/const_app_variant.dart` 统一变体常量、`scripts/build_weidouzi.sh` 本地一键构建、KEYSTORE_SETUP.md 微豆子章节
- **fix** v2 split-per-abi 模式潜在编译冲突：`--split-per-abi` 触发的 `splits.abi` 与 defaultConfig 既有的 `ndk.abiFilters` 在 AGP 中互斥（`Conflicting configuration : 'arm64-v8a' in ndk abiFilters cannot be present when splits abi filters are set`），v2 一直没人跑过所以隐藏至今。改为只保留 `--target-platform android-arm64`（与 ndk.abiFilters 兼容），由 ndk.abiFilters=arm64-v8a 负责 AAR 过滤、--target-platform 负责 Flutter 引擎与 native 库限制 → 产物 ~36MB 单 arm64 APK，与原计划的"主动瘦身"效果一致，不走 splits.abi 这条冲突分支
- **feat** 主构建（v1）共享 pubspec 版本号：新增 push tags `v*` 触发，新增 `build-weidouzi` job 与小豆子 job 并列（不依赖）。小豆子产出上传 `fr_latest_apk`（小豆子主更新源）；微豆子产出上传 `wdz_latest_apk`（微豆子主更新源，应用内直接消费）+ tag 触发时额外传 `wdz_v<version>_apk`（去 v 前缀，永久指向该 tag）。两套上传均与小豆子同等严谨度：双重 sha256 校验 + 3 次重试 + 不上 PR 触发。第一发布版 v1.0.0（对应 pubspec 1.0.0+1）
- **feat(lab)** api_test_demo 改为「APK 下载管理」：原双 Tab（APK 更新 + 语音合成）改为单滚动页 + 两张可下载 APK 卡——「FR 最新版 APK」与「微豆子 最新版」。每张卡自管理 metadata + 下载/暂停/续传/取消/安装/分享 状态，用参数化的 `ApkDownloadEndpoint`（fileKey 注入）实现双向下载。完全砍掉语音合成 Tab 与 `lib/lab/demos/api_test/api_speech_tab.dart`。`ApkDownloadEndpoint._fileKey` 从 static const 改为构造参数，默认仍 = `kApkFileKey`（保持 `api_client` / `apk_download_service` 调用方零改动）。`ApkDownloadManager` 仍保留（`ApkAutoUpdateHost` + `runApkAutoDownloadOnStartup` 的小豆子自启动检查还在跑）

## 2026-10-13

### 界面 / 导航（ui / nav）

- **fix** AI 板块回归「一个模块」：`3544137a` 移除 AI 导航组时把 AI 助手页一并带出目录（设置页 AI Tab、`NavGroup.ai`、6 条 `ai-*` 拆分条目全删），AI 在底栏 / 设置页彻底不可达，只剩 `fr://lab/core/home` 深链。本次在核心组补回 **1 条** `core-ai`「AI 中心」→ `HomePage`：AI 不再拆成多个钉选单元，也不再缺席；Agent / Format / 小票 / 小助手 / pi 仍由页内 `kAssistantEntries` 列表承载
- **fix!** SVG 图标换色失效根因修复：色值替换缺 `#` 前缀（`fill="7A9A7E"` 非法色，flutter_svg 回退默认色）——此前 Lab 卡片 / 详情弹窗 / 收藏格子的图标颜色实际未生效。补 `#` 后轮廓随 `colors.text`、强调点随 `colors.accent` 真正生效；`colorizeLabSvg` 测试出口锁死
- **fix** 底栏选中 / 未选中无区别：`_toHex` 丢弃 alpha，未选中态 `primary@42%` 被渲染成全亮度。半透明色改输出 8 位 `#RRGGBBAA`（flutter_svg 支持），选中态明暗差恢复
- **feat** 强调点明度差自适应：主题 primary 与轮廓明度差 < 0.28 时自动调整——亮色主题（cobalt 深宝蓝 / zen 深鼠尾草）强调点提亮到 L0.62，深色主题（暮紫 / 暗黑）轮廓压暗 35% 让 primary 成为最亮元素；恢复设计稿「深轮廓 + 中高亮强调」的对比关系，全部站点（卡片 / 导航 / 设置 / 收藏）一处生效
- **feat** 「更多」弹窗格子支持拖拽排序（复用 lab 收藏同款 ReorderableBuilder）：longPressDelay 缩短到 200ms、feedback 放大 1.06（iOS 触弹）、拖动项带 18px 阴影在 sheet 明底上浮起、起拖/收拖轻触震动反馈；sheet 包 Consumer 让 setPins 后立即重建列表（不用关弹窗再开）。`_MoreCell` 转 StatefulWidget，叠加 `_PressCurve`（8% 过冲弹簧曲线，1.0→1.08→1.0）实现按下微弹放大 + 松手弹回原大小，配合 `HapticFeedback.selectionClick()` 给 iOS 触控节奏
- **test** `test/app_lifecycle/more_sheet_drag_test.dart`：NavPinsNotifier.setPins 重组（visible 段保留 / overflow 段重排）+ sanitize 兜底 + `PressBounceCurve` 4 个关键节点（t=0/0.35/0.7/1）
- **feat** 底栏钉选条 SVG 图标改双色：轮廓随选中态着色，强调点恒走主题自适应强调色——cobalt / zen 这类深 primary 主题在底栏也能看到醒目强调点
- **fix** 「更多」弹窗格子应用图标改双色：`NavEntryIcon(tint: cs.primary)` 让 body 与自适应 accent 都落回主色（zen/cobalt 等 mid-单色主题看起来是单色）——改用 `tint: cs.onSurface`（深轮廓）+ 自适应强调点，恢复深浅对比 mini-app-icon 观感
- **feat** SVG 图标铺进导航三处：底栏钉选条（`_NavTab` 轮廓随选中态着色）、设置页钉选 / 组件启用行首图标（`_LeadingIcon` onPrimaryContainer 轮廓 + 自适应强调点）、⋯ 溢出面板（`_MoreCell` onSurface 轮廓 + 自适应强调点）。新增 `NavEntry.labIconAsset` 字段 + `NavEntryIcon` 统一渲染器（SVG 优先 / Material icon 兜底），核心入口与未登记 demo 自动走兜底

### 主题（theme）

- **feat** 深色主题按钮规则落地：暮紫 / 暗黑下 FilledButton / ElevatedButton / FAB / SnackBar 从「primary 亮色实心块」改为「暗底 surfaceContainerHighest + 白字 + 1px outline 细边 + 主题色强调」，SnackBar 不再是 inverseSurface 亮块（334 处调用一处不改全量生效）；专注首页「今日专注」大卡同步分支为暗底细边卡 + 纯白数字 + 主题色引导语，去掉 primary 辉光；亮色四套主题保持 primary 实色不变。`dark_theme_test` 新增按钮规则组锁死 7 套主题的底 / 前 / 边断言
- **feat** 第 7 套独立主题「暗黑」：中性石墨无彩系（primary `#C9C5BD` 暖中性浅石墨、surface `#131311`、surfaceContainerHighest `#0C0C0A` 贴近 OLED 纯黑），与暮紫（冷紫 + 鎏金）明确区隔；AppColorsExtension 按 graphite 无彩规则衍生（灰绿 success / 灰琥珀 warning / 灰蓝 info + 8 位石墨 category）；`materialThemeModeProvider` 深色映射补 dark 分支（原 switch 只列 purple，dark 会错落到 light）；主题页按 `AppThemeMode.values` 自动出现第 7 张卡，状态层 / 持久化零改动

### 实验室框架（lab）

- **feat** 接入 `assets/lab-demo-icons/` 的 48 张 SVG 图标作为 demo 标准图标集，覆盖三处：Lab 卡片网格左上角、demo 详情弹窗标题、下拉面板收藏格子（原来一律星星占位）。每个 SVG 渲染时把设计稿硬编码的 `#2B3445`（主轮廓）替换为当前主题 `colors.text`、`#5B7CFA`（强调点）替换为 `colors.accent`——切换主题卡片图标随之变色。SVG 字符串按 asset 缓存（去重 + 单次 loadString），启动期预热 48 张避免首次打开 Lab 闪烁；未登记图标的后增 demo（session-host）回退原通用图标
- **test** 新增 `test/lab/lab_icon_test.dart`：主 slug 全部有专属 SVG 映射（白名单例外）、48 张全部登记、全部可从 bundle 加载且含主题色替换锚点（单色图标如时钟不强求强调色锚点，集合级断言覆盖度）

### 界面 / 导航（ui / nav）

- **fix** 钉选「统一登录 / 会话托管」等自身不铺背景的 demo 底栏根页露黑窗：主壳 Scaffold 恢复主题底色兜底（此前主壳与 DemoDetailPage 壳根页双层透明，一路透到 Flutter 黑窗）
- **feat** 底栏末位槽直连「设置」：钉选数不超过可见槽（容量 −1）且设置未被钉选时，末位不再显示 ⋯，点一下直接进设置；有溢出或设置已被钉在可见槽时保持原 ⋯ 行为

## 2026-10-12

### 远程输入（remotetype）

- **fix** 自动重连不稳定：加应用层心跳（15s ping / 45s 无响应判死）探针半开连接——此前切网/NAT 超时后本地 socket 半开、`isConnected` 恒真，自动重连永不触发、发送静默进黑洞（手动重连是整会话重建所以总能救活，两路径行为不一致的根因）；重试从单次改为 1.5s/4s/8s 三轮退避梯，全部失败才弹最终断开
- **fix** 输入框换行 bug：composer 从 `Expanded` 回退为固定高度（148）——expands 输入框随键盘伸缩时高度抖动，IME 重建合成区会把换行搅进正文；输入页同时改为全页面布局（不做底栏避让预留，底栏是浮层且键盘弹出自动隐藏），清空/重放按钮上移到顶部工具行，内容整体贴上排布
- **feat** 快捷键条改横向滑动 + 显示配置：托盘从多行堆叠改为单行横向滑动；新增「显示」入口，可配置「只显示名字 / 显示按键明细（×N·ms + 逐条 chord 预览）」与「单行 / 双行」，配置持久化
- **feat** 重放按钮：PC 端焦点丢失导致注入没落进目标框时，可一键把当前输入框全文重打（先发空快照清 PC 端 mirror，再重发全文，绕过 mirror diff 的无变化判定）
- **refactor** 移除内置语音按钮与 `speech_to_text` 依赖：语音走手机输入法自带听写，识别文本直接落输入框共用全文同步管线；回车「发送 / 换行」从通栏大 tab 改为紧凑小开关，纵向空间让给输入区
- **fix** 断线自动重连：socket 断开不再立刻弹「连接断开」，先静默重连一次，成功无感恢复、失败才提示；页面切回时对托管会话同样只重试一次
- **fix** 序列编排里的卡片拖不动（`ReorderableDragStartListener` 未绑定手柄）
- **feat** 快捷键编排改自绘虚拟键盘 + 序列宏：5 行 QWERTY + 折叠 Fn 区点按录入，一条快捷键 = 多个 chord + 毫秒间隔（0–1000ms 可调），触发按序发送；数据模型升级 v2 并兼容旧数据（`chords + intervalMs`）
- **feat** 接入 DemoSessionHost：退出页面不断连、回前台自动重连
- **feat** 输入页按茶禅原型重排；统一登录下连接 401 修复
- **refactor** `rt_page` 拆分为板块文件（1417 → 594 行）

### 实验室框架（lab）

- **feat** demo-scope 治理三步走：scope 契约 + 会话托管骨架（P0）、RemoteType 接入（P1）、空闲回收协程 + 会话托管监视面板 + 审计登记（P2）

### 界面 / 设置（ui / settings / theme）

- **feat** 六主题体系：新增宝蓝 cobalt，rose / ink / lemon / purple 按色卡重配
- **feat** 设置列表重排（钉选散卡 / 分组大组卡）；通用 Tab 新增「统一登录扫码」快捷入口
- **refactor** 底栏去通栏底轨、设置 Tab 改 PageView 横向滑动、底栏避让切回每页自加留白
- **fix** 底栏 Stack 浮层挂载 + 毛玻璃胶囊 + 键盘避让；`_NavTab` 文字槽固定防中文度量撑破；全屏 demo 不参与键盘 resize

## 2026-10-11

### 远程输入（remotetype）

- **feat** 接入统一登录：登录后静默铸 mn-rt 凭据，列出「我名下的电脑」点一下即连
- **feat** 输入页快捷键面板：预设组合键点按即发
- **feat** 回车注入双模式：发送（Enter）/ 换行（Shift+Enter）随快照即时切换
- **fix** 输入页固定高度不被键盘挤压

### 认证（auth）

- **feat** 统一登录改为原生表单（去掉 WebView 授权页）；新增 authhub 后端模块 + token 层双签发方
- **feat** 统一登录 · 扫码批准 Lab（auth-login）
- **fix** 客户端不再持有 refresh_token；扫码批准 preview 路径缺失修复；登录态与业务 token 两份凭据各归其位
- **fix** APK 后台下载 start 指令竞态导致自动下载失效

### 界面（ui）

- **feat** 主壳底栏透明液态玻璃近似
- **fix** 游戏中心 / 房间就绪对齐主题浮卡壳；大厅 / 设置配色回归 theme primary；快捷底栏根页隐藏无效返回键

## 2026-10-10

### 远程输入（lab）

- **feat!** 固定三 Tab 底栏重构为可钉选 / 可重排 / 可搜索 / 可观测的快捷导航
- **feat** 启动期游戏封面 KV 预热 + 设置页接真实缩略图
- **fix!** 语音不同步真正根因——`onChanged` 捕获不到「结束合成」帧
- **fix** ASR `error_busy` 根因修复——楔死识别器强制销毁重建 + 自动重试
- **feat** iOS 手感升级：滑动分段胶囊 / 列表拖拽 Q 弹 / 内容页弹簧切换
- **fix** ⋯ 模态面板「设置」点击无反应 + pop 后 setState 时序错乱
