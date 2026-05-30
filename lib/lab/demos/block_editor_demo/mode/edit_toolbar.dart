import 'package:flutter/material.dart';
import '../../../../core/note/note_root_scope.dart';
import 'toolbar_mode.dart';
import '../state.dart';
import '../type_panel.dart';

class EditToolbar implements ToolbarMode {
  VoidCallback? onImportMdFile;
  VoidCallback? onImportMdText;

  void setImportCallbacks({VoidCallback? onImportMdFile, VoidCallback? onImportMdText}) {
    this.onImportMdFile = onImportMdFile;
    this.onImportMdText = onImportMdText;
  }

  @override
  String get name => 'edit';

  @override
  void onModeEnter() {}

  @override
  void onModeExit() {}

  @override
  Widget buildBody(BuildContext context, EditorState editorState, Widget body) => body;

  @override
  Widget build(BuildContext context, EditorState editorState, VoidCallback onSwitchMode) {
    return Container(
      color: Theme.of(context).canvasColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...NoteRootScope.of(context).noteRoot.availableTypes.map(
                        (info) => _toolbarTypeButton(context, editorState, info),
                      ),
                      const SizedBox(width: 8),
                      _toolbarButton(
                        label: '导入文件',
                        icon: Icons.description,
                        onTap: onImportMdFile ?? () {},
                      ),
                      _toolbarButton(
                        label: '导入文字',
                        icon: Icons.paste,
                        onTap: onImportMdText ?? () {},
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Material(
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => TypePanel.show(context, editorState),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Icon(Icons.expand_less, size: 22, color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarTypeButton(BuildContext context, EditorState editorState, BlockTypeInfo info) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: info.label,
        child: Material(
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => editorState.addBlockWithType(info.prototype),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Icon(info.icon, size: 20, color: Colors.grey[600]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Icon(icon, size: 20, color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}
