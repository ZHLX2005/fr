import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart' hide RichText;
import 'package:file_picker/file_picker.dart';
import '../../../core/note/note_root_scope.dart';
import '../../../services/media_service.dart';
import '../../../lab/lab_container.dart';
import 'state.dart';
import 'card.dart';
import 'note_panel.dart';
import 'type_panel.dart';

/// 块编辑器 Demo（持久化版）
class BlockEditorDemo extends StatefulWidget {
  const BlockEditorDemo({super.key});

  @override
  State<BlockEditorDemo> createState() => _BlockEditorDemoState();
}

class _BlockEditorDemoState extends State<BlockEditorDemo> {
  late EditorState _editorState;
  bool _editorStateReady = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_editorStateReady) {
      _editorState = EditorState(
        noteFactory: NoteRootScope.of(context).noteRoot,
      );
      _editorStateReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorState.init();
      });
    }
  }

  @override
  void initState() {
    super.initState();
  }

  Widget _buildBottomToolbar() {
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
                        (info) => _toolbarTypeButton(info),
                      ),
                      const SizedBox(width: 8),
                      _toolbarButton(
                        label: '导入文件',
                        icon: Icons.description,
                        onTap: () => _importMdFile(),
                      ),
                      _toolbarButton(
                        label: '导入文字',
                        icon: Icons.paste,
                        onTap: () => _showImportMdTextDialog(),
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
                  onTap: () => TypePanel.show(context, _editorState,
                    onImportMdFile: () => _importMdFile(),
                    onImportMdText: () => _showImportMdTextDialog(),
                  ),
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

  Widget _toolbarTypeButton(BlockTypeInfo info) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: info.label,
        child: Material(
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _editorState.addBlockWithType(info.prototype),
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

  Future<void> _importMdFile() async {
    final result = await MediaService.pickFile(
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    String source;
    if (file.bytes != null) {
      source = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      source = await File(file.path!).readAsString();
    } else {
      return;
    }

    _editorState.importMd(source);
  }

  Future<void> _showImportMdTextDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入 Markdown'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '粘贴 Markdown 文本...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _editorState.importMd(result);
    }
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _editorState,
      builder: (context, _) {
        final blocks = _editorState.blocks;
        final selectedId = _editorState.selectedId;

        return Scaffold(
          appBar: AppBar(
            title: const Text('块编辑器'),
            actions: [
              IconButton(
                icon: const Icon(Icons.menu_open),
                onPressed: () {
                  _scaffoldKey.currentState?.openEndDrawer();
                },
                tooltip: '笔记列表',
              ),
            ],
          ),
          key: _scaffoldKey,
          endDrawer: NotePanel(editorState: _editorState),
          bottomNavigationBar: _buildBottomToolbar(),
          body: blocks.isEmpty
              ? const Center(child: Text('暂无内容，点击 ☰ 新建笔记'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: blocks.length + 1,
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex == blocks.length || newIndex == blocks.length) return;
                    _editorState.moveBlock(oldIndex, newIndex);
                  },
                  proxyDecorator: _proxyDecorator,
                  itemBuilder: (context, index) {
                    if (index == blocks.length) {
                      return GestureDetector(
                        key: const ValueKey('__add_block__'),
                        onTap: () => _editorState.addBlock(),
                        behavior: HitTestBehavior.translucent,
                        child: const SizedBox(height: 60),
                      );
                    }
                    return BlockCard(
                      key: ValueKey(blocks[index].id),
                      block: blocks[index],
                      isSelected: blocks[index].id == selectedId,
                      editorState: _editorState,
                    );
                  },
                ),
        );
      },
    );
  }
}

class BlockEditorDemoPage extends DemoPage {
  @override
  String get title => '块编辑器';

  @override
  String get description => '结构化块树笔记编辑器 — 持久化存储';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const BlockEditorDemo();
}

void registerBlockEditorDemo() {
  demoRegistry.register(BlockEditorDemoPage());
}
