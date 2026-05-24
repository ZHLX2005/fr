import 'package:flutter/material.dart';
import '../../../core/note/core/models/block_type.dart';
import 'state.dart';

/// 分类展示所有 BlockType 的展开面板（底部弹出）。
class TypePanel extends StatelessWidget {
  final EditorState editorState;

  const TypePanel({super.key, required this.editorState});

  static Future<void> show(BuildContext context, EditorState editorState) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => TypePanel(editorState: editorState),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('插入块', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategory('标题', _headingTiles()),
                    _buildCategory('列表', [
                      _typeTile(context, Icons.check_box_outline_blank, '待办', BlockType.todo),
                      _typeTile(context, Icons.format_list_bulleted, '无序列表', BlockType.bulletListItem),
                      _typeTile(context, Icons.format_list_numbered, '有序列表', BlockType.orderedListItem),
                    ]),
                    _buildCategory('文本', [
                      _typeTile(context, Icons.text_fields, '段落', BlockType.paragraph),
                      _typeTile(context, Icons.format_quote, '引用', BlockType.quote),
                      _typeTile(context, Icons.code, '代码', BlockType.code),
                      _typeTile(context, Icons.info_outline, '提示框', BlockType.callout),
                    ]),
                    _buildCategory('媒体', [
                      _typeTile(context, Icons.image, '图片', BlockType.image),
                      _typeTile(context, Icons.horizontal_rule, '分割线', BlockType.divider),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategory(String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey[500])),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tiles,
          ),
        ],
      ),
    );
  }

  List<Widget> _headingTiles() {
    return List.generate(6, (i) {
      final level = i + 1;
      return _HeadingTile(level: level, editorState: editorState);
    });
  }

  Widget _typeTile(BuildContext context, IconData icon, String label, BlockType type) {
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          editorState.addBlockWithType(type);
          Navigator.of(context).maybePop();
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 20, color: Colors.grey[700]),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadingTile extends StatelessWidget {
  final int level;
  final EditorState editorState;

  const _HeadingTile({required this.level, required this.editorState});

  @override
  Widget build(BuildContext context) {
    final sizes = [24.0, 20.0, 17.0, 15.0, 13.0, 12.0];
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          editorState.addBlockWithType(BlockType.heading, level: level);
          Navigator.of(context).maybePop();
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            'H$level',
            style: TextStyle(
              fontSize: sizes[level - 1],
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
