import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/note/note.dart';

/// 仿 wolai/息流/Notion 的笔记编辑器 Demo
class NoteEditorDemo extends DemoPage {
  @override
  String get title => '笔记编辑器';

  @override
  String get description => '仿 wolai/息流/Notion 的 AI 笔记编辑器原型';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const NoteEditorPage();
  }
}

void registerNoteEditorDemo() {
  demoRegistry.register(NoteEditorDemo());
}
