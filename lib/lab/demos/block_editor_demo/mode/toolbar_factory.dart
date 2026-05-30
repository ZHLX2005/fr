import 'package:flutter/material.dart';
import '../state.dart';
import 'toolbar_mode.dart';
import 'edit_toolbar.dart';
import 'chat_bar.dart';

class BottomToolbarFactory extends ChangeNotifier {
  final _registry = <String, ToolbarMode>{};
  String _currentMode = 'edit';

  BottomToolbarFactory() {
    final chat = ChatBar();
    chat.onStateChanged = notifyListeners;
    register(chat);
    register(EditToolbar());
  }

  String get currentMode => _currentMode;

  void register(ToolbarMode mode) {
    _registry[mode.name] = mode;
  }

  void switchTo(String mode) {
    if (mode == _currentMode) return;
    _registry[_currentMode]?.onModeExit();
    _currentMode = mode;
    _registry[_currentMode]?.onModeEnter();
    notifyListeners();
  }

  Widget build(BuildContext context, EditorState editorState) {
    final mode = _registry[_currentMode];
    if (mode == null) return const SizedBox.shrink();
    return mode.build(
      context,
      editorState,
      () => _switchToNext(),
    );
  }

  Widget buildBody(BuildContext context, EditorState editorState, Widget body) {
    final mode = _registry[_currentMode];
    if (mode == null) return body;
    return mode.buildBody(context, editorState, body);
  }

  void _switchToNext() {
    final modes = _registry.keys.toList();
    final idx = modes.indexOf(_currentMode);
    if (idx < 0) return;
    final nextName = modes[(idx + 1) % modes.length];
    switchTo(nextName);
  }

  void setImportCallbacks({VoidCallback? onImportMdFile, VoidCallback? onImportMdText}) {
    final edit = _registry['edit'] as EditToolbar?;
    edit?.setImportCallbacks(onImportMdFile: onImportMdFile, onImportMdText: onImportMdText);
  }
}
