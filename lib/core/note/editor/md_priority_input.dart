import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// MD 优先输入控制器
///
/// 监听用户输入，在"输入空格后"识别行首模式：
/// - "# " → H1（并删除 "# "）
/// - "## " → H2（并删除 "## "）
/// - "- " → 无序列表（并删除 "- "）
/// - "> " → 引用（并删除 "> "）
///
/// 这是 wolai 的关键：用户按 md 语法打字，编辑器优先理解并转成富文本
class MarkdownPriorityInputController {
  final quill.QuillController controller;

  StreamSubscription? _sub;
  bool _armed = true;
  Timer? _rearm;

  MarkdownPriorityInputController({required this.controller});

  void start() {
    _sub = controller.document.changes.listen((event) {
      if (!_armed) return;
      if (event.source != quill.ChangeSource.local) return;

      if (!_isInsertedSingleSpace(event.change)) return;

      final sel = controller.selection;
      final cursor = sel.baseOffset;
      if (cursor <= 0) return;

      final plain = controller.document.toPlainText();
      if (cursor > plain.length) return;

      // 刚插入的空格位于 cursor-1
      if (plain[cursor - 1] != ' ') return;

      // 找到行首
      final lineStart = _findLineStart(plain, cursor - 1);
      final prefix = plain.substring(lineStart, cursor);

      // 按优先级匹配（从长到短，避免前缀覆盖）
      if (prefix == '###### ') {
        _applyBlockAndRemovePrefix(lineStart, 7, quill.Attribute.h6);
      } else if (prefix == '##### ') {
        _applyBlockAndRemovePrefix(lineStart, 6, quill.Attribute.h5);
      } else if (prefix == '#### ') {
        _applyBlockAndRemovePrefix(lineStart, 5, quill.Attribute.h4);
      } else if (prefix == '### ') {
        _applyBlockAndRemovePrefix(lineStart, 4, quill.Attribute.h3);
      } else if (prefix == '## ') {
        _applyBlockAndRemovePrefix(lineStart, 3, quill.Attribute.h2);
      } else if (prefix == '# ') {
        _applyBlockAndRemovePrefix(lineStart, 2, quill.Attribute.h1);
      } else if (prefix == '- ') {
        _applyBlockAndRemovePrefix(lineStart, 2, quill.Attribute.ul);
      } else if (prefix == '> ') {
        _applyBlockAndRemovePrefix(lineStart, 2, quill.Attribute.blockQuote);
      }
    });
  }

  int _findLineStart(String plain, int index) {
    for (int i = index; i >= 0; i--) {
      if (plain[i] == '\n') return i + 1;
    }
    return 0;
  }

  void _applyBlockAndRemovePrefix(int lineStart, int prefixLen, quill.Attribute attr) {
    _armed = false;
    _rearm?.cancel();

    try {
      // 删除前缀
      controller.document.delete(lineStart, prefixLen);

      // 回退光标
      final oldCursor = controller.selection.baseOffset;
      final newCursor = (oldCursor - prefixLen).clamp(0, controller.document.toPlainText().length);
      controller.updateSelection(
        TextSelection.collapsed(offset: newCursor),
        quill.ChangeSource.local,
      );

      // 应用 block attribute
      controller.formatSelection(attr);
    } finally {
      _rearm = Timer(const Duration(milliseconds: 120), () => _armed = true);
    }
  }

  bool _isInsertedSingleSpace(dynamic delta) {
    try {
      final ops = (delta as dynamic).toJson() as List<dynamic>;
      final inserts = ops.where((e) => e is Map && e.containsKey('insert')).toList();
      if (inserts.length != 1) return false;
      return inserts.first['insert'] == ' ';
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _rearm?.cancel();
    _sub?.cancel();
  }
}
