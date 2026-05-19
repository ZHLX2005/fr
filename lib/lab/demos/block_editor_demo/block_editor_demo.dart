import 'package:flutter/material.dart' hide RichText;
import '../../../core/note/core/block_type.dart';
import '../../../lab/lab_container.dart';
import 'state.dart';
import 'data.dart';
import 'card.dart';

/// 块编辑器 Demo（Phase 1：核心编辑）
class BlockEditorDemo extends StatefulWidget {
  const BlockEditorDemo({super.key});

  @override
  State<BlockEditorDemo> createState() => _BlockEditorDemoState();
}

class _BlockEditorDemoState extends State<BlockEditorDemo> {
  final _editorState = EditorState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editorState.load(createDemoBlocks());
    });
  }

  Widget _buildBottomToolbar() {
    return Container(
      color: Theme.of(context).canvasColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _toolbarTypeButton('P', BlockType.paragraph, Icons.text_fields),
                      const SizedBox(width: 2),
                      _toolbarHeadingButtons(),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('☐', BlockType.todo, Icons.check_box_outline_blank),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('•', BlockType.bulletListItem, Icons.format_list_bulleted),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('1.', BlockType.orderedListItem, Icons.format_list_numbered),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('"', BlockType.quote, Icons.format_quote),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('<>', BlockType.code, Icons.code),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('—', BlockType.divider, Icons.horizontal_rule),
                      const SizedBox(width: 2),
                      _toolbarTypeButton('💡', BlockType.callout, Icons.info_outline),
                    ],
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(icon, size: 18, color: Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _toolbarHeadingButtons() {
    return SizedBox(
      height: 32,
      child: Row(
        children: [1, 2, 3].map((l) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Material(
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _editorState.addBlockWithType(BlockType.heading, level: l),
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
                icon: const Icon(Icons.add),
                onPressed: () => _editorState.addBlock(),
                tooltip: '新增块',
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomToolbar(),
          body: blocks.isEmpty
              ? const Center(child: Text('暂无内容，点击 + 新增块'))
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
  String get description => '结构化块树笔记编辑器原型 — 类型切换、删除、新增';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const BlockEditorDemo();
}

void registerBlockEditorDemo() {
  demoRegistry.register(BlockEditorDemoPage());
}
