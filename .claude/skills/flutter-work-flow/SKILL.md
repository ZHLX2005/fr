---
name: flutter-work-flow
description: flutter的开发操作流程,在任何问题都需要优先加载这个SKILL
---
1. 完成代码之后,优先执行web -release 最低成本的检查编译报错
2. 然后执行run -chrome 启动在容器当中,在web当中进行运行 指定端口10086,如果这个端口被占用 就中断 保证这个端口被你使用 flutter run -d chrome --web-port 10086
3. 如果没有报错,每次完成代一次commit都需要推送到github上,让github完成流水线构建apk,也就是说本地是没有java相关的开发环境 所有的debug都是通过web实现
