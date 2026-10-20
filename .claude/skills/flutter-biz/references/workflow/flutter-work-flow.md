---
name: flutter-work-flow
description: flutter的开发操作流程,在dart-flutter任何问题都需要优先加载这个SKILL（含 fr:// 路由/Lab 容器/时间页/游戏中心/API 模块/Hive 存储/课表/WebRTC 等扩展 SOP 与问题方案）
---
`<doc-reference>`
references/   # 序列化命名（A03）：A=扩展SOP（动手扩展一个模块前读） B=问题与方案（遇到 bug / 做方案选择时读） C=专项子系统深水区（带子 ref 的领域专用指南）
├── A01-Flutter-fr路由-注册规范与防腐蚀.md   # fr:// 日常使用：新页面注册SOP + 防腐蚀grep检测 + 反模式（加新页面/写跳转时读）
├── A02-Flutter-自定义Scheme路由中心化-fr-Router.md   # fr:// 路由机制：authority/path 拆分 + prefix 匹配 + handler 模式（理解系统/重构时读）
├── A03-Flutter-Lab容器-模块结构与重构模式.md   # lab/ 目录地图（lab_panel/demo_grid/game_center）+ ValueNotifier 双通道 + 手势收敛 + part→import 拆法
├── A04-Flutter-TimePage-Focus时间模块完整指南.md   # 整 time 模块单一长 ref：架构 + 加新工作流 / 改面板 / 统计与心流扩展 / Lab 过滤+深链 4 章（time 主题同源不拆文件）
├── A05-Flutter-游戏中心-扩展游戏路线.md   # 加新游戏/新分类/新封面图案的扩展点地图 + SOP（数据流/封面三级来源/真坑）
├── A06-Flutter-Demo-slug别名与Tab合并SOP.md   # demo 别名注册（旧 fr:// URL 兼容）+ 多 demo 合并 Tab 容器 SOP
├── A07-Flutter-API模块规范-目录即后端与拦截器链.md   # lib/api/ 模块规范：目录=后端 + 深目录轻文件 + 拦截器链 + 5 条异味检测命令（含 Notion 3 步上传）
├── A08-Flutter-Hive存储工作流-调试与最佳实践.md   # typed box 泛型访问 / 调试步骤 / 删除 key 类型处理 / StorageManager 集中面板（box 读写/删除/类型报错时读）
├── A09-Flutter-Hive-存储面板BoxDescriptor注册制.md   # BoxDescriptor / StorageRegistry / StorageManager 原理 + 手写 TypeAdapter + 新 feature 4 步（设计面板存储时读）
├── A10-Flutter-Hive-新模块存储Checklist.md   # 5 铁律（meta 集中/formatter 独立/typeId 常量）+ Step1-7 范本 + 仓库层统一（建带 Hive 模块时读）
├── B01-Flutter-Provider双重实例冲突-时钟wipe后数据恢复.md   # 根级/页面级双 Provider 各写同一 SP，wipe 后被旧实例定时快照回写
├── B02-Flutter-Hive-TypeAdapter-part文件CI构建失败问题.md   # Hive part文件CI构建连续失败3次,通过合并Adapter到主文件解决
├── B03-Android-FloatingWindow-常驻截屏模式适配Android14+.md   # Android 14+ MediaProjection token 一次性问题，常驻 VirtualDisplay 方案
├── B04-Flutter-CollapsingHeader圆角渐变头部与白色内容区布局.md   # CustomScrollView + SliverPersistentHeader 实现圆角渐变头部，关键：pinned:false，只用gradient不用color
├── B05-Flutter-Reorderable网格阴影容器拖拽掉帧-RepaintBoundary隔离.md   # 同款 ReorderableBuilder 页面流畅/弹窗掉帧：宿主 blur 阴影无 RepaintBoundary 隔离，每帧动画重绘大阴影；附 BottomSheet 下拉关闭手势竞争备忘
├── C01-Flutter-TimeTable课表模块-架构与扩展指南.md   # lib/core/timetable/ 模块地图 + E1-E4 扩展 SOP + 12 条关键机制勿破坏表（改课表任何文件时读）
├── C02-WebRTC-视频通话基础设施与结构设计.md   # 信令→媒体→DataChannel→移动端 7 步架构指南 + 错误案例（实现 WebRTC 视频通话/P2P 时读）
├── C03-Flutter-TimeTable-追剧模式专项.md   # 剧模型 SSOT / buildAnimeDsl / AnimeSourceAdapter 适配层 / 排期编辑页（扩展追剧模式时读）
└── C04-Flutter-TimeTable-追剧后端API契约.md   # 自建新番后端 /api/v1/anime/season 唯一契约（联调/改契约字段时读）
`</doc-reference>`

## 序列总览（先读这里）

| 代号 | 类别 | 何时读该序列 | 成员 |
| --- | --- | --- | --- |
| A | 扩展 SOP | 动手扩展一个模块前（成本 / 范围 / 流程） | A01 fr路由注册 / A02 fr路由机制 / A03 Lab容器 / A04 TimePage / A05 游戏中心 / A06 Demo-slug别名 / A07 API模块 / A08 Hive存储工作流 / A09 存储面板注册制 / A10 存储Checklist |
| B | 问题与方案 | 遇到具体 bug / 做细节方案选择时单独读 | B01 Provider双实例 / B02 Hive CI坑 / B03 FloatingWindow适配 / B04 CollapsingHeader / B05 Reorderable阴影容器掉帧 |
| C | 专项子系统 | 进入课表 / WebRTC 等独立子系统深水区时（子系统主干 + 特化子 ref） | C01 课表模块 / C02 WebRTC / C03 追剧专项 / C04 追剧API契约 |

## 何时读哪个 ref

| 代号 | ref | 何时读取 |
| --- | --- | --- |
| A01 | Flutter-fr路由-注册规范与防腐蚀 | **加新页面 / 写 fr:// 跳转 / 加 MethodChannel / 提交前自查腐蚀时** |
| A02 | Flutter-自定义Scheme路由中心化-fr-Router | **改 fr:// 路由 / 重构路由系统 / 理解路由设计原理时** |
| A03 | Flutter-Lab容器-模块结构与重构模式 | **改 lib/screens/profile/lab/ 任何文件（Lab页/下拉面板/游戏中心/demo卡片）/ 给重手势+重动画页面做性能或模块化重构时** |
| A04 | Flutter-TimePage-Focus时间模块完整指南 | **改中间 Time tab 任何文件 / 改 timePage 标记 / kTimePageMeta / 心流空间 / Lab timePage 过滤 / 桌面 widget 深链时**（整 time 模块单一长 ref：架构 + 4 章 + 3 错误案例） |
| A05 | Flutter-游戏中心-扩展游戏路线 | **往游戏中心加新游戏 / 加新分类 / 加新封面图案时**（扩展点地图 + 加游戏SOP + 封面三级来源 + slug拼错等真坑） |
| A06 | Flutter-Demo-slug别名与Tab合并SOP | **给 demo 加别名 slug（旧 URL 兼容）/ 合并多个相关 demo 为统一 Tab 容器时** |
| A07 | Flutter-API模块规范-目录即后端与拦截器链 | **新增 API 端点 / 接入新后端 / 业务代码要发 HTTP 请求 / lib/api/ 防腐蚀自查 / 改 Notion 端点时** |
| A08 | Flutter-Hive存储工作流-调试与最佳实践 | **Hive box 读写/删除报错（type 不匹配/closed box）/ 存储面板看不到新 box 或显示 "Instance of xxx" / 新写 Hive 存储入口时** |
| A09 | Flutter-Hive-存储面板BoxDescriptor注册制 | **设计新 feature 的 Hive 存储结构 / 手写 TypeAdapter / 想理解 `Lab → 存储分析` 面板注册制原理时** |
| A10 | Flutter-Hive-新模块存储Checklist | **新建带 Hive 存储的模块时**（meta 集中 / formatter 独立 / init 四件套 / 仓库层统一 反模式自查） |
| B01 | Flutter-Provider双重实例冲突-时钟wipe后数据恢复 | **Provider 擦数据后快照恢复 / 根级和页面级都有同一 Provider / wipe 失效 / 定时写 SP 的 Provider 行为异常时** |
| B02 | Flutter-Hive-TypeAdapter-part文件CI构建失败问题 | Hive TypeAdapter / part 文件 CI 编译失败时 |
| B03 | Android-FloatingWindow-常驻截屏模式适配Android14+ | Android 14+ MediaProjection / 悬浮窗截屏 / token 失效时 |
| B04 | Flutter-CollapsingHeader圆角渐变头部与白色内容区布局 | 做 collapsing header / 圆角渐变头部布局时 |
| B05 | Flutter-Reorderable网格阴影容器拖拽掉帧-RepaintBoundary隔离 | **同款拖拽一处流畅一处掉帧 / ReorderableBuilder 放进带阴影 sheet 或卡片时**（含 BottomSheet 手势竞争备忘） |
| C01 | Flutter-TimeTable课表模块-架构与扩展指南 | **改 lib/core/timetable/ 任何文件（新增模式/数据源适配器/DSL 语法/显示配置/多空间）/ 改 timetable_repository 时**（C03/C04 的入口 ref） |
| C02 | WebRTC-视频通话基础设施与结构设计 | **实现 WebRTC 视频通话 / 设计 P2P 实时通信 / 搭建信令基础设施 / 音视频或 DataChannel 传输 / 移动端实时通信优化时** |
| C03 | Flutter-TimeTable-追剧模式专项 | **扩展/修改追剧模式**（剧模型 / 适配层 / 排期编辑器 / 生成器 / 反推）时 |
| C04 | Flutter-TimeTable-追剧后端API契约 | **自建新番后端契约联调 / 新增 SelfHostedAnimeAdapter / 改动 anime 契约字段时** |

import: 任何不能立即完成的任务,请使用todolist相关的工具 先规划任务 然后再每个条目进行完成 禁止没有任何流程的进行代码控制

1. 完成代码之后,优先执行在根目录执行  flutter analyze  | grep error  或者flutter build web --release发现错误  进行最低成本的检查编译报错
1b. ⚠ **提交前必须跑 codegen 步骤**：`dart run build_runner build --delete-conflicting-outputs`
   （= CI「Generate code」步骤的同款命令，~50s）。`flutter analyze` **查不出**这一类问题 ——
   SDK 自带 analyzer 与 build_runner 内置 analyzer **版本不同**，后者更旧。
   典型症状：新写的 Dart 语法本地 analyze 全绿，CI 却报
   `SEVERE] json_serializable on xxx.dart: This builder requires Dart inputs without syntax errors`
   → **"Expected an identifier"**，整条 APK 流水线红在 Generate code（~1m48s 就挂，
   后面所有步骤全 skipped）。
   已踩过的具体语法（2026-10-20）：**null-aware 集合元素** `?key: value` / `?value`
   （Dart 3.8+ 特性）。SDK analyzer 认得、CI builder 的 analyzer 不认得。
   → 本项目 map/list 里放可空值一律用 `if (x != null) x: v` 写法；
   若非要用 null-aware 元素，必须加 `// ignore_for_file: use_null_aware_elements`
   并**同时**确认 CI 的 Generate code 步骤是绿的。
   （仓库现状：除该次误用外，`lib/` `test/` 全仓无 null-aware 元素用法。）
2. 如果没有报错,每次完成一次commit都需要推送到github上,让github完成流水线构建apk(本地无 java 开发环境,所有 debug 通过 web 实现);你只能 add、commit 自己变更的文件,禁止使用 add . / commit .
3. 提交前先 git status 逐条确认改动归属 —— 只提交本次任务产生的文件;并行开发时工作区可能混入他人未提交改动,误提交会把别人的在制品一并推上去
4. 对于没有被编译导入的文件 因为文件的孤立无法及时报错,所有使用flutter analyze进行孤儿dart文件的分析,你完全不要执行flutter run指令,这是是一个安卓项目,不需要思考web和ios,如果修改了Android目录的内容 必须执行flutter build apk进行验证测试
5. 如果需要多文件的结构分离 有两个方案提供选择: **在a.  lab/demos下面存在的demo页面应该是单文件，扁平化，如果需要其他文件辅助，请创建lab/demos/(模块名)/扩展文件.dart的文件，进行管理， b . 当指名只是一个严格的高度扩展的项目,请在core/{模块}创建独立的完整文件设计 在lab/demos当中,通过**

  @override

  WidgetbuildPage(BuildContextcontext) {

    return  constXXXXXXPage();

  }进行导入   (注释: 可以参考经典案例:a方案: api_test_demo.dart  b方案: word_drag_demo  ,以及无任何文件解耦,单文件的方案 crash_log_demo)  , 一般不进行文件解耦,如果超过400行 就必须使用方案a ,方案b需要用户主动进行指定,按照代码量选择方案a或者无解耦

规范:

1. 因为跨端的布局差别很大,所有优先使用各种具有百分比,自动编排的布局方式,降低各种边缘键的压缩问题
2. 内部元素能够居中就居中,对于一些卡片, 能够自动布局 就自动布局,
3. 对于一些枚举,比如颜色卡表,如果存在两排的情况,请自动把第一排的一些元素布局到第二排,两排的数量差异小于2,自动平衡多排之间的数量差异
4. !! 一个模块当中的常量 请创建const_xxxx.dart文件 进行统一管理 减少维护 成本

场景规范

LAB_DEMO:

1. 不要在 lab 里创建多余的返回按钮 —— 外部 DemoPage 已有包装,直接用它的默认返回按钮。如果原始 page 自带左上角返回按钮,设 `bool get preferFullScreen => true`。创建新 lab 前先阅读 lab_container.dart(新 lab 一般还没有容器)
2. \+ 按钮创建元素 只需要一个+即可
3. 请查看/lib/lab/demos相关的工程目录的用法,进行模块学习和扩展模块

native目录:

1. 连接安卓原生的相关功能做桥接,桥接工具统一管理,统一放到 lib/native 下面

提示:

1. 对于困难的任务 请使用现成的组件库
2. 对于特殊任务,请使用指定的项目源码进行参考,提取出核心代码,具有隔离性的代码

检查:

1. 完成之后先检查编译是否成功
2. 检查相关配置是否真正实现,尤其是安卓原生项目的权限配置 —— 每次添加新依赖,确认是否需要在安卓当前配置对应权限或通信通道
3. 竭尽全力避免溢出问题
4. ⚠ 提交前跑 `dart run build_runner build --delete-conflicting-outputs`（见上文 1b）——
   这是 CI 流水线里唯一 `flutter analyze` 覆盖不到的失败点
