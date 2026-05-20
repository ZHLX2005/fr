/// AI Tool Use 定义
///
/// 定义 AI 可以调用的工具列表。每个工具对应一个 [BlockOp]。
class AiTool {
  final String name;
  final String description;
  final Map<String, ToolParam> params;

  const AiTool(this.name, this.description, this.params);

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': {
            'type': 'object',
            'properties': {
              for (final entry in params.entries)
                entry.key: {
                  'type': entry.value.type,
                  'description': entry.value.description,
                },
            },
            'required': params.entries.where((e) => e.value.required).map((e) => e.key).toList(),
          },
        },
      };
}

class ToolParam {
  final String type;
  final String description;
  final bool required;

  const ToolParam(this.type, this.description, {this.required = true});
}

/// 预定义的工具列表
class AiToolbox {
  static const tools = [
    AiTool(
      'read_block',
      '读取指定块的完整信息，包括内容、类型和元数据',
      {'id': ToolParam('string', '块的 ID')},
    ),
    AiTool(
      'read_subtree',
      '读取以指定块为根的子树，递归展开到指定深度',
      {
        'id': ToolParam('string', '根块 ID'),
        'depth': ToolParam('integer', '递归深度（1-5）'),
      },
    ),
    AiTool(
      'search_blocks',
      '在文档中搜索文字，返回匹配的块列表',
      {
        'query': ToolParam('string', '搜索关键字'),
        'scope_id': ToolParam('string', '搜索范围（块 ID），不传则搜索全文', required: false),
        'limit': ToolParam('integer', '最大返回数', required: false),
      },
    ),
    AiTool(
      'insert_block',
      '在页面中插入新块。不传 after_id 则追加到末尾，不传 type 默认为 paragraph。大段文字推荐用 write_content。',
      {
        'content': ToolParam('string', '块的文字内容'),
        'type': ToolParam('string', '可选：paragraph/heading/todo/quote/code/divider/bullet_list_item/ordered_list_item', required: false),
        'after_id': ToolParam('string', '在哪个块之后插入，不传则追加到末尾', required: false),
        'parent_id': ToolParam('string', '父块 ID，不传则为根节点', required: false),
        'data': ToolParam('string', 'JSON 格式的类型专属数据', required: false),
      },
    ),
    AiTool(
      'update_block',
      '更新指定块的内容、类型或元数据',
      {
        'id': ToolParam('string', '块 ID'),
        'content': ToolParam('string', '新文字内容', required: false),
        'type': ToolParam('string', '新块类型', required: false),
        'data': ToolParam('string', 'JSON 格式的更新数据', required: false),
      },
    ),
    AiTool(
      'delete_block',
      '删除指定块及其所有子块',
      {'id': ToolParam('string', '块 ID')},
    ),
    AiTool(
      'move_block',
      '移动块到新位置',
      {
        'id': ToolParam('string', '块 ID'),
        'parent_id': ToolParam('string', '新父块 ID'),
        'after_id': ToolParam('string', '同级中在哪个块之后', required: false),
      },
    ),
    AiTool(
      'merge_blocks',
      '将源块的内容合并到目标块，然后删除源块',
      {
        'source_id': ToolParam('string', '源块 ID'),
        'target_id': ToolParam('string', '目标块 ID'),
      },
    ),
    AiTool(
      'split_block',
      '在指定偏移位置将一个块分割为两个块',
      {
        'id': ToolParam('string', '块 ID'),
        'split_offset': ToolParam('integer', '分割位置（字符偏移量）'),
      },
    ),
    AiTool(
      'format_text',
      '对指定块内的文字应用格式',
      {
        'id': ToolParam('string', '块 ID'),
        'start_offset': ToolParam('integer', '起始偏移'),
        'end_offset': ToolParam('integer', '结束偏移'),
        'format': ToolParam('string', '格式：bold/italic/inline_code/strikethrough'),
      },
    ),
    AiTool(
      'ai_create_page',
      '创建新页面并将 Markdown 内容填入页面',
      {
        'title': ToolParam('string', '页面标题'),
        'content': ToolParam('string', 'Markdown 格式的页面内容，会被解析为块插入', required: false),
        'after_page_id': ToolParam('string', '在哪个页面之后创建，不传则追加到最后', required: false),
      },
    ),
    AiTool(
      'write_content',
      '将 Markdown 内容写入当前页面。自动解析 # 标题、- 列表、> 引用等语法为对应块。写作类任务首选此工具。',
      {
        'content': ToolParam('string', 'Markdown 格式的内容'),
        'replace': ToolParam('boolean', '是否替换当前页面所有内容（默认 false 表示追加）', required: false),
      },
    ),
  ];

  /// 生成 tool_use 的 JSON 定义
  static List<Map<String, dynamic>> toJsonList() =>
      tools.map((t) => t.toJson()).toList();
}
