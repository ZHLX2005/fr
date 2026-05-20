import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import '../../core/note/blocks/blocks.dart';
import '../../core/note/workspace/workspace.dart';

/// 块树笔记编辑器 Demo
class NoteEditorDemo extends DemoPage {
  @override
  String get title => '笔记编辑器';

  @override
  String get description => '结构化块树笔记编辑器原型，支持多页面工作区和 AI 创建页面';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WorkspaceProvider()..init(),
      child: const BlockEditorPage(),
    );
  }
}

void registerNoteEditorDemo() {
  demoRegistry.register(NoteEditorDemo());
}
