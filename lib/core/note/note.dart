// Core note module - 仿 wolai/息流/Notion 的笔记编辑器
//
// 阶段1: 基础设施搭建 → 关键体验闭环
// - Quill 编辑器 + 底部 MD 风格按钮
// - MD 优先输入：# / - / > / ## + 空格自动转样式
// - 新行行首空格唤起 AI 输入框 → 插入 ai:xx
// - Embed 卡片（弱块）跑通

export 'const_note.dart';

export 'services/ai_service.dart';

export 'editor/note_editor.dart';
export 'editor/space_ai_trigger.dart';
export 'editor/md_priority_input.dart';
export 'editor/md_actions.dart';

export 'embed/embed_card_builder.dart';

export 'bridges/markdown_bridge.dart';
