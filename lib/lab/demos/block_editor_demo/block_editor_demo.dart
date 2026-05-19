import 'package:flutter/material.dart' hide RichText;
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
          body: blocks.isEmpty
              ? const Center(child: Text('暂无内容，点击 + 新增块'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: blocks.length,
                  itemBuilder: (context, index) {
                    return BlockCard(
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
  Widget buildPage(BuildContext context) => const BlockEditorDemo();
}

void registerBlockEditorDemo() {
  demoRegistry.register(BlockEditorDemoPage());
}
