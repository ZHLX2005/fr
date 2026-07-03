---
name: flutter-work-flow
description: flutter的开发操作流程,在dart-flutter任何问题都需要优先加载这个SKILL
---
`<doc-reffence>`
.reffenrece/
├── Flutter-Hive-TypeAdapter-part文件CI构建失败问题.md   # Flutter Hive part文件CI构建连续失败3次,通过合并Adapter到主文件解决
├── Flutter-CollapsingHeader圆角渐变头部与白色内容区布局.md   # CustomScrollView + SliverPersistentHeader 实现圆角渐变头部，关键：pinned:false，只用gradient不用color
├── Android-FloatingWindow-常驻截屏模式适配Android14+.md   # Android 14+ MediaProjection token 一次性问题，常驻 VirtualDisplay 方案
├── 修复warning.md   # Flutter analyze warning 修复经验汇总
├── Flutter-自定义Scheme路由中心化-fr-Router.md   # fr:// 路由设计：authority/path 拆分 + prefix 匹配 + handler 模式（理解系统/重构时读）
└── Flutter-fr路由-注册规范与防腐蚀.md   # fr:// 日常使用：新页面注册SOP + 防腐蚀grep检测 + 反模式（加新页面/写跳转时读）
`</doc-reffence>`

## 何时读哪个 ref

| ref | 何时读取 |
|---|---|
| Flutter-Hive-TypeAdapter-part文件CI构建失败问题 | Hive TypeAdapter / part 文件 CI 编译失败时 |
| Flutter-CollapsingHeader圆角渐变头部与白色内容区布局 | 做 collapsing header / 圆角渐变头部布局时 |
| Android-FloatingWindow-常驻截屏模式适配Android14+ | Android 14+ MediaProjection / 悬浮窗截屏 / token 失效时 |
| 修复warning | flutter analyze 出现 warning 需要修复时 |
| Flutter-自定义Scheme路由中心化-fr-Router | **改 fr:// 路由 / 重构路由系统 / 理解路由设计原理时** |
| Flutter-fr路由-注册规范与防腐蚀 | **加新页面 / 写 fr:// 跳转 / 加 MethodChannel / 提交前自查腐蚀时** |



import: 任何不能立即完成的任务,请使用todolist相关的工具 先规划任务 然后再每个条目进行完成 禁止没有任何流程的进行代码控制

1. 完成代码之后,优先执行在根目录执行  flutter analyze  | grep error  或者flutter build web --release发现错误  进行最低成本的检查编译报错
2. 如果没有报错,每次完成代一次commit都需要推送到github上,让github完成流水线构建apk,也就是说本地是没有java相关的开发环境 所有的debug都是通过web实现,你只能add,commit自己变更的文件,禁止使用add . commit .
3. 如果没有报错,每次完成代一次commit都需要推送到github上,让github完成流水线构建apk,也就是说本地是没有java相关的开发环境 所有的debug都是通过web实现
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

1. 不要创建返回按钮,因为外部已经存在包装了,不要创建多余的<-返回按钮按钮,如果原始page有左上角返回的按钮,就boolgetpreferFullScreen=>true; 我更加倾向于使用DemoPage提供的默认返回按钮,你创建新的lab的时候,一般是没有lab的,先阅读lab_container.dart文件
2. \+ 按钮创建元素 只需要一个+即可
3. 请查看/lib/lab/demos相关的工程目录的用法,进行模块学习和扩展模块

native目录:

1. 连接安卓原生的相关功能 进行桥接 ,对交接的工具 进行统一的管理
2. 连接安卓原生的相关功能 进行桥接 ,对交接的工具 进行统一的管理!!!!!! 放到lab/native下面

提示:

1. 对于困难的任务 请使用现成的组件库
2. 对于特殊任务,请使用指定的项目源码进行参考,提取出核心代码,具有隔离性的代码

检查:

1. 完成之后1.检查编译的成功
2. 检查相关的配置是否实实现,尤其是安卓原生项目对应的权限配置,每次添加一个新的依赖,请检查是否要在 安卓当前配置相关权限或者沟通通道
3. 竭尽全力避免溢出的问题
