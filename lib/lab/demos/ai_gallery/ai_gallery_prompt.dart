/// 重试用的提示词拼装。
///
/// 场景：模型返回的东西解析不了（缺括号、包了 markdown、字段类型不对…）。
/// 盲目原样重发同一段提示词，模型多半再犯一次同样的错 —— 所以把**解析器
/// 的错误原文**当成新证据塞回提示词里，让它知道自己上一轮错在哪。
///
/// 纯函数、零依赖，便于单测。
library;

/// 回填上一次回复时的默认截断长度（字符数）。
///
/// 太短模型看不到出错位置，太长会把重试请求的 token 成本翻倍 ——
/// 800~1200 是「够看清错误 + 不炸预算」的折中。
const int kRetryReplySnippetChars = 1000;

/// 构造「带解析错误回执」的重试提示词。
///
/// * [basePrompt] 用户配置的原始提示词（每次都保留，避免多轮重试后偏离目标）；
/// * [attempt] 这是第几次重试（从 1 开始，用于让模型知道已重复犯错）；
/// * [error] 解析器/请求异常的可读文本（就是日志里那行）；
/// * [previousReply] 上一次模型的原始回复（API 调用失败时为空）。
String buildGalleryRetryPrompt({
  required String basePrompt,
  required int attempt,
  required String error,
  String previousReply = '',
  int snippetChars = kRetryReplySnippetChars,
}) {
  final b = StringBuffer()
    ..writeln(basePrompt.trimRight())
    ..writeln()
    ..writeln('-----')
    ..writeln('【第 $attempt 次重试：你上一次的输出没有通过校验】')
    ..writeln('错误信息：${_oneLine(error)}');

  final reply = previousReply.trim();
  if (reply.isEmpty) {
    b.writeln('上一次请求没有拿到任何回复内容，请重新分析图片后输出。');
  } else {
    final snippet = reply.length > snippetChars
        ? '${reply.substring(0, snippetChars)}…（后略）'
        : reply;
    b
      ..writeln('你上一次的实际输出（节选）：')
      ..writeln('<<<')
      ..writeln(snippet)
      ..writeln('>>>');
  }

  b
    ..writeln('请对照上面的错误修正后重新输出：')
    ..writeln('1. 只输出一个 JSON 对象，第一个字符是 {，最后一个字符是 }；')
    ..writeln('2. 不要 markdown 代码块标记，不要前后解释文字，不要注释，不要尾随逗号；')
    ..writeln('3. 键名与字符串一律用英文双引号，缺失的字段按上面的要求补全；')
    ..writeln('4. 字段契约与第一次请求完全一致，不要改名、不要少字段。');
  return b.toString();
}

/// 把多行异常压成一行，避免日志正文被堆栈式文本撑爆。
String _oneLine(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length > 400 ? '${flat.substring(0, 400)}…' : flat;
}
