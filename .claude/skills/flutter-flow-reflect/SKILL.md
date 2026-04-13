---
name: flutter-flow-reflect
description: 当解决完成了一个长期的bug,或者完成了最后的修复,请调用这个工具,实现工作流程的反思
---
这是一个增强SKILLS的元skill,用于增强指定增强流程和参考文档 避免有价值的东西被遗漏

请把这次对话最关键的工作修改和处理思路沉淀到这目录

.claude/skills/flutter-work-flow/reffenrece下

第一步总结当前的所有对话,添加一份文档到

.claude/skills/flutter-work-flow/reffenrece下

要求:

1. 中文文件名 并且做到见面知意,md文档的名称是越能说明解决xx场景的xx问题,越是一个好文件名
2. 包含完整的项目背景介绍 , 关键的一些难点和技术点
3. 如果关于bug修复,内容请完成强调 nok_eg以及ok_eg,修复的思路和原理 以及进行 /brainstorm 思考有没有更加专业的解决方案

第二步

更新 .claude/skills/flutter-work-flow/SKILL.md 添加目录相关的介绍 保持同步,并且添加充分的注释,说明清楚情况

`<doc-reffence>`

./reffenrece/
├── xxxx0.md        # 文件注释
├── xxxx1.md     # 文件注释

`</doc-reffence>`

要求: 1.使用相对路径 .reffennce/xxxx.md  便于 AI 引用 ,添加到.claude/skills/flutter-work-flow/SKILL.md的 `<doc-reffence>`区块当中

2. 不要修改SKILL的主流程,只需要提示AI新的文档创建在什么地方
3. 你对SKILL.md的修改只能存在于 `<doc-reffence>`xxxx `</doc-reffence>`的标签对当中,你添加的内容只是介绍文档,使用目录加注释的方式进行介绍. 以下格式不是必要的:
4. 严禁其他的引导,比如在 `doc-reffence`当中添加类似的引导: "归档说明: 每次完成重大bug修复或重要功能后,调用 xxx 沉淀文档至此目录"
