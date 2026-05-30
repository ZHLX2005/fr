import 'package:flutter/material.dart';
import '../state.dart';

abstract class ToolbarMode {
  String get name;
  Widget build(
    BuildContext context,
    EditorState editorState,
    VoidCallback onSwitchMode,
  );
  Widget buildBody(BuildContext context, EditorState editorState, Widget body) => body;
  void onModeEnter() {}
  void onModeExit() {}
}
