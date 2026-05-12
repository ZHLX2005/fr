import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';

/// 触发上下文：给 AI 的上下文窗口
class NewLineInvokeContext {
  /// 光标前的内容（不含触发空格）
  final String beforeCursor;

  /// 触发位置的偏移量
  final int triggerOffset;

  NewLineInvokeContext({
    required this.beforeCursor,
    required this.triggerOffset,
  });
}

/// 侦测规则：
/// - 当用户"插入空格"
/// - 且该空格发生在"新的一行的行首"
/// - 且该行除了这个空格外没有其它内容
/// => 触发 onInvoke，并把那一个空格回滚删除
class NewLineSpaceDetector {
  final quill.QuillController controller;
  final Future<void> Function(NewLineInvokeContext ctx) onInvoke;

  StreamSubscription? _sub;
  bool _armed = true;
  Timer? _rearmTimer;

  NewLineSpaceDetector({
    required this.controller,
    required this.onInvoke,
  });

  void start() {
    _sub = controller.document.changes.listen((event) async {
      if (!_armed) return;

      // 只响应用户本地输入
      if (event.source != quill.ChangeSource.local) return;

      // 仅识别"插入单个空格"的变更
      final insertedSpace = _isInsertedSingleSpace(event.change);
      if (!insertedSpace) return;

      final sel = controller.selection;
      final cursor = sel.baseOffset;

      if (cursor <= 0) return;

      final plain = controller.document.toPlainText();
      if (cursor > plain.length) return;

      // 插入发生后，光标在空格之后，所以 plain[cursor - 1] 是刚插入的空格
      final justInsertedChar = plain[cursor - 1];
      if (justInsertedChar != ' ') return;

      // 检查前一个字符是否是换行或文档开头（行首）
      final prevChar = (cursor - 2) >= 0 ? plain[cursor - 2] : null;
      final atLineStart = prevChar == null || prevChar == '\n';
      if (!atLineStart) return;

      // 检查该行是否为空（空格后的下一个字符是换行或不存在）
      final nextChar = cursor < plain.length ? plain[cursor] : null;
      final lineStillEmpty = nextChar == null || nextChar == '\n';
      if (!lineStillEmpty) return;

      // 命中：先撤销这个空格
      _armed = false;
      _rearmTimer?.cancel();

      try {
        final deleteOffset = cursor - 1;
        controller.document.delete(deleteOffset, 1);
        controller.updateSelection(
          TextSelection.collapsed(offset: deleteOffset),
          quill.ChangeSource.local,
        );

        // 构造上下文
        final ctxText = controller.document.toPlainText();
        final ctxCursor = deleteOffset.clamp(0, ctxText.length);
        final start = (ctxCursor - 800).clamp(0, ctxCursor);
        final before = ctxText.substring(start, ctxCursor);

        await onInvoke(NewLineInvokeContext(
          beforeCursor: before,
          triggerOffset: deleteOffset,
        ));
      } finally {
        // 延迟 re-arm，避免 onInvoke 插入文本引发二次触发
        _rearmTimer = Timer(const Duration(milliseconds: 250), () {
          _armed = true;
        });
      }
    });
  }

  bool _isInsertedSingleSpace(Delta delta) {
    try {
      final ops = delta.toJson() as List<dynamic>;
      final inserts = ops.where((e) => e is Map && e.containsKey('insert')).toList();
      if (inserts.length != 1) return false;
      final ins = inserts.first['insert'];
      return ins == ' ';
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _rearmTimer?.cancel();
    _sub?.cancel();
  }
}
