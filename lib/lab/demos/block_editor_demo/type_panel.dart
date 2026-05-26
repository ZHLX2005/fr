import 'package:flutter/material.dart' hide RichText;
import '../../../core/note/note_root_scope.dart';
import '../../../core/note/widget/widget.dart';
import 'state.dart';

/// 分类展示所有 BlockType 的展开面板（底部弹出）。
class TypePanel extends StatelessWidget {
  final EditorState editorState;
  final VoidCallback? onImportMd;

  const TypePanel({super.key, required this.editorState, this.onImportMd});

  static Future<void> show(BuildContext context, EditorState editorState, {VoidCallback? onImportMd}) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => TypePanel(editorState: editorState, onImportMd: onImportMd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = NoteRootScope.of(context).noteRoot.availableTypes;
    final grouped = <BlockTypeCategory, List<BlockTypeInfo>>{};
    for (final info in types) {
      grouped.putIfAbsent(info.category, () => []).add(info);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32, height: 3,
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
                    for (final cat in BlockTypeCategory.values) ...[
                      if (grouped.containsKey(cat))
                        _buildCategory(cat.label,
                          grouped[cat]!.map((info) => _typeTile(context, info)).toList()),
                    ],
                    if (onImportMd != null)
                      _buildCategory('工具', [
                        _actionTile(context, Icons.description, '导入 MD', onImportMd!),
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
          Wrap(spacing: 6, runSpacing: 6, children: tiles),
        ],
      ),
    );
  }

  Widget _actionTile(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          onTap();
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

  Widget _typeTile(BuildContext context, BlockTypeInfo info) {
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          editorState.addBlockWithType(info.prototype);
          Navigator.of(context).maybePop();
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            children: [
              Icon(info.icon, size: 20, color: Colors.grey[700]),
              const SizedBox(height: 2),
              Text(info.label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            ],
          ),
        ),
      ),
    );
  }
}
