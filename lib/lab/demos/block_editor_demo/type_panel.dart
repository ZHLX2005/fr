import 'package:flutter/material.dart' hide RichText;
import '../../../core/note/note_root_scope.dart';
import 'state.dart';

/// 分类展示所有 BlockType 的展开面板（底部弹出）。
class TypePanel extends StatelessWidget {
  final EditorState editorState;
  final VoidCallback? onImportMd;
  final VoidCallback? onImportMdText;

  const TypePanel({
    super.key,
    required this.editorState,
    this.onImportMd,
    this.onImportMdText,
  });

  static Future<void> show(
    BuildContext context,
    EditorState editorState, {
    VoidCallback? onImportMdFile,
    VoidCallback? onImportMdText,
  }) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => TypePanel(
        editorState: editorState,
        onImportMd: onImportMdFile,
        onImportMdText: onImportMdText,
      ),
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
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '插入块',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cat in BlockTypeCategory.values) ...[
                      if (grouped.containsKey(cat))
                        _buildCategory(
                          context,
                          cat.label,
                          grouped[cat]!
                              .map((info) => _typeTile(context, info))
                              .toList(),
                        ),
                    ],
                    if (onImportMd != null || onImportMdText != null)
                      _buildCategory(context, '工具', [
                        if (onImportMd != null)
                          _actionTile(
                            context,
                            Icons.description,
                            '导入文件',
                            onImportMd!,
                          ),
                        if (onImportMdText != null)
                          _actionTile(
                            context,
                            Icons.paste,
                            '导入文字',
                            onImportMdText!,
                          ),
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

  Widget _buildCategory(
    BuildContext context,
    String title,
    List<Widget> tiles,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: tiles),
        ],
      ),
    );
  }

  Widget _actionTile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: colors.surfaceContainerHighest,
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
              Icon(icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeTile(BuildContext context, BlockTypeInfo info) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: colors.surfaceContainerHighest,
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
              Icon(info.icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                info.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
