---
name: flutter-work-flow
description: flutter的开发操作流程,在dart-flutter任何问题都需要优先加载这个SKILL
---
`<doc-reffence>`
.reffenrece/
├── Flutter-Hive-TypeAdapter-part文件CI构建失败问题.md   # Flutter Hive part文件CI构建连续失败3次,通过合并Adapter到主文件解决
└── Flutter-CollapsingHeader圆角渐变头部与白色内容区布局.md   # CustomScrollView + SliverPersistentHeader 实现圆角渐变头部，关键：pinned:false，只用gradient不用color
`</doc-reffence>`

import: 任何不能立即完成的任务,请使用todolist相关的工具 先规划任务 然后再每个条目进行完成 禁止没有任何流程的进行代码控制

1. 完成代码之后,优先执行flutter build web --release 进行最低成本的检查编译报错
2. 如果没有报错,每次完成代一次commit都需要推送到github上,让github完成流水线构建apk,也就是说本地是没有java相关的开发环境 所有的debug都是通过web实现,你只能add,commit自己变更的文件,禁止使用add . commit .
3. 如果没有报错,每次完成代一次commit都需要推送到github上,让github完成流水线构建apk,也就是说本地是没有java相关的开发环境 所有的debug都是通过web实现
4. 对于没有被编译导入的文件 因为文件的孤立无法及时报错,所有使用flutter analyze进行孤儿dart文件的分析,你完全不要执行flutter run指令,这是是一个安卓项目,不需要思考web和ios
5. 

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

提示:

1. 对于困难的任务 请使用现成的组件库
2. 对于特殊任务,请使用指定的项目源码进行参考,提取出核心代码,具有隔离性的代码

检查:

1. 完成之后1.检查编译的成功
2. 检查相关的配置是否实实现,尤其是安卓原生项目对应的权限配置,每次添加一个新的依赖,请检查是否要在 安卓当前配置相关权限或者沟通通道
3. 竭尽全力避免溢出的问题
