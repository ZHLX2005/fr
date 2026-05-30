import 'package:flutter/material.dart';
import '../state.dart';

abstract class ToolbarMode {
  String get name;
  Widget build(
    BuildContext context,
    EditorState editorState,
    VoidCallback onSwitchMode,
  );
  void onModeEnter() {}
  void onModeExit() {}
}
