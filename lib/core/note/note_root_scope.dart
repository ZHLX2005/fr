import 'package:flutter/material.dart';
import 'factory.dart';

/// 通过 InheritedWidget 向 widget 子树提供 [NoteFactory]。
///
/// 在 [main] 中创建 [NoteFactory] 实例之后，用此 widget
/// 包裹应用根节点，子树中的 widget 即可通过 [NoteRootScope.of] 访问。
class NoteRootScope extends InheritedWidget {
  final NoteFactory noteRoot;

  const NoteRootScope({
    required this.noteRoot,
    required super.child,
  });

  static NoteRootScope of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<NoteRootScope>();
    assert(result != null, 'No NoteRootScope found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(NoteRootScope oldWidget) => oldWidget.noteRoot != noteRoot;
}
