import '../../api_client.dart';
import '../../api_response.dart';

/// 文章编辑端点 — AI 驱动的内容修改/问答服务。
///
/// ## 后端闭环流程
/// 后端 goframe 收到请求后，在内存中执行以下流程（无需前端参与）：
///
/// ```text
/// 请求 → GoFrame POST /api/v1/article/edit
///         │
///         ├─ 注入 API 配置到 context
///         ├─ 创建 article_master Agent（Supervisor 模式）
///         │   ├─ sub_editor（持 apply_article_diff 工具）
///         │   └─ sub_qa（纯问答，无工具）
///         ├─ 组装 prompt（TOML 全文 + 行号标注 → LLM 精准 diff）
///         ├─ Agent 事件流：
///         │   ├─ ❓ 问答意图 → sub_qa → 直接回复
///         │   └─ ✏️ 编辑意图 → sub_editor → 生成 git diff
///         │       → 调用 apply_article_diff 工具（修改内存中的 TOML）
///         │       → 捕获修改后的 TOML + 工具摘要
///         └─ 返回 { diff, conclusion, modified_toml, has_edit }
/// ```
///
/// [ArticleEditResponse.hasEdit] 真实区分了两种意图：
/// - `true` → LLM 判断为编辑请求，调用了 `apply_article_diff` 工具
/// - `false` → LLM 判断为纯问答，直接回复（[ArticleEditResponse.diff] 为空）
class ArticleEndpoint {
  final ApiClient _client;

  ArticleEndpoint(this._client);

  /// 编辑文章 — 一次请求完成意图识别 + 工具调用 + 验证的完整闭环。
  ///
  /// 参数 [apiKey] — LLM 供应商 API Key（如 deepseek / openai / anthropic）。
  ///   必填。用于后端创建 ChatModel 实例，由 [article_master] Agent 透传给子 agent。
  ///
  /// 参数 [articleToml] — 文章全文（TOML 格式的块文档）。
  ///   必填。结构为由 [[blocks]] 组成的列表，每个 block 包含：
  ///   - `id` — 全局唯一块标识（如 "blk-h1"、"blk-p1"）
  ///   - `type` — 块类型（heading / paragraph / code / todo / callout / ...）
  ///   - `content` — 富文本内容（支持 **加粗** *斜体* `行内代码` [链接]）
  ///   - `attrs.*` — 类型专属属性（如 heading.level、code.language、todo.checked）
  ///   - `children` — 子块列表（嵌套结构，如 toggle > paragraph、bullet_list_item 嵌套）
  ///   后端的 article_master Agent 收到后自动添加行号标注，辅助 LLM 精准生成 git diff。
  ///
  /// 参数 [prompt] — 用户对文章的操作要求。
  ///   必填。自然语言描述，后端的 [article_master] 先做意图识别（路由到 sub_editor 或 sub_qa），
  ///   再由子 agent 执行。示例：
  ///   - 编辑："把 blk-p1 中的'深刻改变'改为'悄然改变'"
  ///   - 新增："在末尾加一段关于未来的展望"
  ///   - 问答："这篇文章的主题是什么？用一句话总结"
  ///   - 删除："删掉 blk-old 那个 divider"
  ///   - 复杂："把所有 heading level=1 降级为 level=2，并在末尾加一个 callout"
  ///
  /// 参数 [model] — LLM 模型名（可选）。
  ///   为空时后端使用默认模型（如 glm-4.7 / deepseek-v4-flash）。
  ///   支持的值取决于后端配置的供应商。
  ///
  /// 参数 [baseUrl] — LLM API 地址（可选）。
  ///   为空时后端使用默认地址（如 https://open.bigmodel.cn/api/anthropic）。
  ///   与 [model] 搭配，可实现模型供应商切换。
  Future<ApiResponse<ArticleEditResponse>> edit({
    required String apiKey,
    required String articleToml,
    required String prompt,
    String? model,
    String? baseUrl,
  }) =>
      _client.request<ArticleEditResponse>(
        method: 'POST',
        path: '/api/v1/article/edit',
        body: {
          'apiKey': apiKey,
          'articleToml': articleToml,
          'prompt': prompt,
          if (model != null && model.isNotEmpty) 'model': model,
          if (baseUrl != null && baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        },
        fromJson: (json) => ArticleEditResponse.fromJson(json),
      );
}

/// 文章编辑响应。
///
/// 后端完成 AI agent 闭环后返回的完整结果。
/// [hasEdit] 快速区分编辑/问答两种场景，前端据此决定如何展示。
class ArticleEditResponse {
  /// git unified format diff — LLM 生成的精准行级修改描述。
  ///
  /// 格式示例：
  /// ```diff
  /// @@ -10,1 +10,1 @@
  /// -content = "旧内容"
  /// +content = "新内容"
  /// ```
  /// 每一行对应：
  /// - `@@ -oldStart,oldCount +newStart,newCount @@` — hunk 头和行号（1-based）
  /// - ` 空格前缀` — 上下文保留行（与原文逐字符匹配）
  /// - `-前缀` — 要删除的行
  /// - `+前缀` — 要新增的行
  ///
  /// 纯问答场景下此字段为空字符串。
  final String diff;

  /// AI 处理结论 — Agent 的最终回复文本。
  ///
  /// 编辑场景包含修改摘要（如"修改完成：新增 1 行，删除 1 行"）+ 操作描述。
  /// 问答场景直接返回回答内容。调用方可直接展示此字段给用户。
  final String conclusion;

  /// 修改后的完整 TOML 文章内容。
  ///
  /// 编辑场景：`apply_article_diff` 工具成功应用 diff 后的全量 TOML。
  /// 纯问答场景：与传入的 [ArticleEndpoint.edit] 参数 [articleToml] 一致（未修改）。
  /// 前端可用此字段替换本地文章状态，避免手动应用 diff。
  final String modifiedToml;

  /// 是否有编辑操作 — 后端意图识别的结果。
  ///
  /// - `true`：LLM 判断为编辑意图，路由到 sub_editor，调用了 `apply_article_diff` 工具。
  ///   此时 [diff] 和 [modifiedToml] 有效。
  /// - `false`：LLM 判断为问答意图，路由到 sub_qa 直接回复。
  ///   此时 [diff] 为空，[modifiedToml] 与输入原文一致。
  ///
  /// 前端的展示策略：
  /// - `hasEdit=true`：优先展示 [diff]（高亮变更）和 [modifiedToml]（全文替换）
  /// - `hasEdit=false`：只展示 [conclusion]，隐藏 diff 区域
  final bool hasEdit;

  const ArticleEditResponse({
    required this.diff,
    required this.conclusion,
    required this.modifiedToml,
    required this.hasEdit,
  });

  factory ArticleEditResponse.fromJson(Map<String, dynamic> json) =>
      ArticleEditResponse(
        diff: json['diff'] as String? ?? '',
        conclusion: json['conclusion'] as String? ?? '',
        modifiedToml: json['modified_toml'] as String? ?? '',
        hasEdit: json['has_edit'] as bool? ?? false,
      );
}
