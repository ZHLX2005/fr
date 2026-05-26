import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart' hide RichText;
import 'package:file_picker/file_picker.dart';
import '../../../core/note/core/core.dart';
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
  final _editorState = EditorState();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorState.init();
    });
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
                      _toolbarTypeButton('P', const ParagraphType(), Icons.text_fields),
                      const SizedBox(width: 2),
                      _toolbarHeadingButtons(),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('☐', const TodoType(), Icons.check_box_outline_blank),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('•', const BulletListItemType(), Icons.format_list_bulleted),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('1.', const OrderedListItemType(), Icons.format_list_numbered),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('"', const QuoteType(), Icons.format_quote),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('<>', const CodeType(), Icons.code),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('—', const DividerType(), Icons.horizontal_rule),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('💡', const CalloutType(), Icons.info_outline),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('🖼', const ImageType(src: ''), Icons.image),
                      const SizedBox(width: 8),
                      _toolbarButton(
                        label: '导入 MD',
                        icon: Icons.description,
                        onTap: () => _importMdFile(),
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
                  onTap: () => TypePanel.show(context, _editorState, onImportMd: () => _importMdFile()),
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

  Widget _toolbarTypeButton(String label, BlockType type, IconData icon) {
    return Material(
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _editorState.addBlockWithType(type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Icon(icon, size: 20, color: Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _toolbarHeadingButtons() {
    return SizedBox(
      height: 36,
      child: Row(
        children: [1, 2, 3].map((l) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Material(
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _editorState.addBlockWithType(HeadingType(level: l)),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 30.0),
                  alignment: Alignment.center,
                  child: Text(
                    'H$l',
                    style: TextStyle(
                      fontSize: [16.0, 14.0, 13.0][l - 1],
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
                  itemCount: blocks.length,
                  onReorder: _editorState.moveBlock,
                  proxyDecorator: _proxyDecorator,
                  itemBuilder: (context, index) {
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
