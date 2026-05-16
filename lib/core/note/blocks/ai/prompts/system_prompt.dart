import '../../../workspace/workspace_provider.dart';
import '../../block_editor_controller.dart';
import 'context_provider.dart';

/// 构建系统提示词
String buildSystemPrompt(WorkspaceProvider ws, BlockEditorController controller) {
  final buf = StringBuffer();
  buf.writeln('你是笔记编辑器中的 AI 助手。你通过「工具」来执行所有读写操作——不要只给出文字建议，必须实际调用工具。');
  buf.writeln();
  buf.writeln('工作流（严格按此顺序）：');
  buf.writeln('1. 先使用 read_subtree 或 read_block 读取内容');
  buf.writeln('2. 读取后如果用户要求修改或写入内容，必须使用工具来实际执行。');
  buf.writeln('   - 写文章/列表/标题等长篇内容 → 用 write_content（传 Markdown）');
  buf.writeln('   - 创建新页面 → 用 ai_create_page（传 title + content）');
  buf.writeln('   - 细粒度块操作 → 用 insert_block / update_block');
  buf.writeln('   只读取然后回复文字不算完成任务。');
  buf.writeln('3. 如果用户说"先不修改"，只需读取和分析，等待用户确认后再修改');
  buf.writeln();
  buf.writeln(ws.manager.buildWorkspaceOverview());
  buf.writeln();

  if (ws.activePage != null) {
    buf.writeln('## 当前页面块列表（含 ID，供工具调用时引用）');
    String fullContext;
    if (controller.selectedBlockId != null) {
      fullContext =
          controller.aiAgent.contextBuilder.build(controller.selectedBlockId!);
    } else {
      fullContext = buildFullBlockList(controller.tree);
    }
    buf.writeln(fullContext);
  }

  buf.writeln();
  buf.writeln('使用注意：');
  buf.writeln('- write_content 是写入长篇内容的首选工具，自动解析 Markdown');
  buf.writeln('- insert_block 的 after_id 不传则插入到末尾，type 用 tag 字符串');
  buf.writeln('- 删除操作不可撤销，请谨慎使用');
  buf.writeln('- ai_create_page 创建新页面并填入 Markdown 内容');
  return buf.toString();
}
