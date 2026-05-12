import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../embed/embed_card_builder.dart';

/// Markdown 桥接类
///
/// 负责 Quill 文档与 Markdown 格式之间的转换
///
/// 注意：原型阶段先保证可用（纯文本），后续再增强为真正 Markdown 导出
class MarkdownBridge {
  MarkdownBridge._();

  /// 导出为纯文本
  ///
  /// 原型阶段：直接使用 Quill 的 toPlainText()
  /// 后续阶段：可增强为真正 Markdown 格式导出
  static String exportToPlainText(quill.Document doc) {
    return doc.toPlainText();
  }

  /// 导出为 Markdown 格式（基础版）
  ///
  /// 当前实现：纯文本 + 简单换行
  /// 后续可增强：转换标题/列表/粗体/引用/代码等到真正 Markdown 语法
  static String exportToMarkdown(quill.Document doc) {
    final plain = doc.toPlainText();
    // 基础实现：直接返回纯文本
    // 后续阶段可增强属性映射
    return plain;
  }

  /// 从 Markdown 导入
  ///
  /// 原型阶段：直接作为纯文本塞入
  /// 后续阶段：可解析 Markdown 语法并转换为 Quill Delta
  static quill.Document importFromMarkdown(String markdown) {
    final d = quill.Document();
    final text = markdown.endsWith('\n') ? markdown : '$markdown\n';
    d.insert(0, text);
    return d;
  }

  /// 从纯文本导入
  static quill.Document importFromPlainText(String text) {
    final d = quill.Document();
    final insertText = text.endsWith('\n') ? text : '$text\n';
    d.insert(0, insertText);
    return d;
  }

  /// 转换 Delta JSON 到 Markdown（后续阶段使用）
  ///
  /// [deltaJson] - Quill Delta 的 JSON 表示
  /// 返回 Markdown 格式字符串
  static String deltaToMarkdown(List<dynamic> deltaJson) {
    // 后续阶段实现
    // 遍历 delta，转换每个操作到对应的 Markdown 语法
    final buffer = StringBuffer();
    for (final op in deltaJson) {
      if (op is Map) {
        if (op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          } else if (insert is Map && insert.containsKey('embed')) {
            // 处理嵌入
            final embed = insert['embed'];
            if (embed is Map && embed['type'] == EmbedTypes.card) {
              buffer.write('[嵌入卡片]');
            }
          }
        }
      }
    }
    return buffer.toString();
  }
}
