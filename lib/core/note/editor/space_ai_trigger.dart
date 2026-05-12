import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// 触发上下文
class NewLineInvokeContext {
  final String beforeCursor;
  final int triggerOffset;

  NewLineInvokeContext({
    required this.beforeCursor,
    required this.triggerOffset,
  });
}

/// 新行行首空格唤醒 AI 输入框
/// 条件：插入空格 + 行首 + 空行
class NewLineSpaceAiBarTrigger {
  final quill.QuillController controller;
  final VoidCallback onShowAiBar;

  StreamSubscription? _sub;
  bool _armed = true;
  Timer? _rearm;

  NewLineSpaceAiBarTrigger({
    required this.controller,
    required this.onShowAiBar,
  });

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

      // 检查是否刚插入的空格
      if (plain[cursor - 1] != ' ') return;

      // 检查是否在行首（前一字符是换行或文档开头）
      final prev = (cursor - 2) >= 0 ? plain[cursor - 2] : null;
      final atLineStart = prev == null || prev == '\n';
      if (!atLineStart) return;

      // 检查该行是否为空（空格后是换行或结束）
      final next = cursor < plain.length ? plain[cursor] : null;
      final lineEmpty = next == null || next == '\n';
      if (!lineEmpty) return;

      _armed = false;
      _rearm?.cancel();

      try {
        // 删除触发空格
        controller.document.delete(cursor - 1, 1);
        controller.updateSelection(
          TextSelection.collapsed(offset: cursor - 1),
          quill.ChangeSource.local,
        );
        onShowAiBar();
      } finally {
        _rearm = Timer(const Duration(milliseconds: 200), () {
          _armed = true;
        });
      }
    });
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
