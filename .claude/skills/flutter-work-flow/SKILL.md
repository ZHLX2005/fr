---
name: flutter-work-flow
description: flutter的开发操作流程,在dart-flutter任何问题都需要优先加载这个SKILL
---
`<doc-reference>`
references/
├── Flutter-Hive-TypeAdapter-part文件CI构建失败问题.md   # Flutter Hive part文件CI构建连续失败3次,通过合并Adapter到主文件解决
├── Flutter-CollapsingHeader圆角渐变头部与白色内容区布局.md   # CustomScrollView + SliverPersistentHeader 实现圆角渐变头部，关键：pinned:false，只用gradient不用color
├── Android-FloatingWindow-常驻截屏模式适配Android14+.md   # Android 14+ MediaProjection token 一次性问题，常驻 VirtualDisplay 方案
├── Flutter-自定义Scheme路由中心化-fr-Router.md   # fr:// 路由设计：authority/path 拆分 + prefix 匹配 + handler 模式（理解系统/重构时读）
├── Flutter-fr路由-注册规范与防腐蚀.md   # fr:// 日常使用：新页面注册SOP + 防腐蚀grep检测 + 反模式（加新页面/写跳转时读）
├── Flutter-DemoPage-slug抽象化与别名机制.md   # kDemoSlugs 全局表迁移到 abstract slug 字段、Demo 别名机制、多 demo 合并为 Tab 容器
├── Flutter-Lab容器-模块结构与重构模式.md   # lab/ 目录地图（lab_panel/demo_grid/game_center）+ ValueNotifier 双通道 + 手势收敛 + part→import 拆法
├── Flutter-TimePage-Focus时间模块完整指南.md   # 整 time 模块单一长 ref：架构 + 加新工作流 / 改面板 / 统计与心流扩展 / Lab 过滤+深链 4 章（time 主题同源不拆文件）
└── Flutter-游戏中心-扩展游戏路线.md   # 加新游戏/新分类/新封面图案的扩展点地图 + SOP（数据流/封面三级来源/真坑）
`</doc-reference>`

## 何时读哪个 ref

| ref                                                  | 何时读取                                                                                                                    |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Flutter-Hive-TypeAdapter-part文件CI构建失败问题      | Hive TypeAdapter / part 文件 CI 编译失败时                                                                                  |
| Flutter-CollapsingHeader圆角渐变头部与白色内容区布局 | 做 collapsing header / 圆角渐变头部布局时                                                                                   |
| Android-FloatingWindow-常驻截屏模式适配Android14+    | Android 14+ MediaProjection / 悬浮窗截屏 / token 失效时                                                                     |
| Flutter-自定义Scheme路由中心化-fr-Router             | **改 fr:// 路由 / 重构路由系统 / 理解路由设计原理时**                                                                 |
| Flutter-fr路由-注册规范与防腐蚀                      | **加新页面 / 写 fr:// 跳转 / 加 MethodChannel / 提交前自查腐蚀时**                                                    |
| Flutter-DemoPage-slug抽象化与别名机制                | **删 kDemoSlugs 迁 abstract slug / 给 demo 加别名 slug / 合并多个 demo 为统一 Tab 容器时**                            |
| Flutter-Lab容器-模块结构与重构模式                   | **改 lib/screens/profile/lab/ 任何文件（Lab页/下拉面板/游戏中心/demo卡片）/ 给重手势+重动画页面做性能或模块化重构时** |
| Flutter-TimePage-Focus时间模块完整指南                | **改中间 Time tab 任何文件 / 改 timePage 标记 / kTimePageMeta / 心流空间 / FocusStatsPage / Lab timePage 过滤 / 桌面 widget 深链时**（整 time 模块单一长 ref：架构 + 4 章 + 4 错误案例）|
| Flutter-游戏中心-扩展游戏路线                        | **往游戏中心加新游戏 / 加新分类 / 加新封面图案时**（扩展点地图 + 加游戏SOP + 封面三级来源 + slug拼错等真坑）          |
| Flutter-Provider双重实例冲突-时钟wipe后数据恢复      | **Provider 擦数据后快照恢复 / 根级和页面级都有同一 Provider / wipe 失效 / 定时写 SP 的 Provider 行为异常时**          |

import: 任何不能立即完成的任务,请使用todolist相关的工具 先规划任务 然后再每个条目进行完成 禁止没有任何流程的进行代码控制

1. 完成代码之后,优先执行在根目录执行  flutter analyze  | grep error  或者flutter build web --release发现错误  进行最低成本的检查编译报错
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

1. 连接安卓原生的相关功能做桥接,桥接工具统一管理,统一放到 lab/native 下面

提示:

1. 对于困难的任务 请使用现成的组件库
2. 对于特殊任务,请使用指定的项目源码进行参考,提取出核心代码,具有隔离性的代码

检查:

1. 完成之后先检查编译是否成功
2. 检查相关配置是否真正实现,尤其是安卓原生项目的权限配置 —— 每次添加新依赖,确认是否需要在安卓当前配置对应权限或通信通道
3. 竭尽全力避免溢出问题
