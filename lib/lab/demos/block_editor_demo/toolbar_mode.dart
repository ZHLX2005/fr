import 'package:flutter/material.dart';
import 'state.dart';

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

class BottomToolbarFactory {
  final _registry = <String, ToolbarMode>{};

  void register(ToolbarMode mode) {
    _registry[mode.name] = mode;
  }

  ToolbarMode? get(String name) => _registry[name];

  Widget build(String name, BuildContext context, EditorState editorState) {
    final mode = _registry[name];
    if (mode == null) return const SizedBox.shrink();
    return mode.build(
      context,
      editorState,
      () {
        final modes = _registry.keys.toList();
        final idx = modes.indexOf(name);
        if (idx < 0) return;
        final nextName = modes[(idx + 1) % modes.length];
        mode.onModeExit();
        editorState.switchTo(nextName);
        _registry[nextName]?.onModeEnter();
      },
    );
  }
}
