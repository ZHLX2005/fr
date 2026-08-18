import 'package:flutter/material.dart' hide RichText;
import '../../../core/note/note_root_scope.dart';
import 'state.dart';

/// 右侧笔记列表面板（Scaffold endDrawer）。
class NotePanel extends StatefulWidget {
  final EditorState editorState;

  const NotePanel({super.key, required this.editorState});

  @override
  State<NotePanel> createState() => _NotePanelState();
}

class _NotePanelState extends State<NotePanel> {
  List<NoteInfo> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotes());
  }

  Future<void> _loadNotes() async {
    try {
      final notes = await NoteRootScope.of(context).noteRoot.listNotes();
      if (mounted) {
        setState(() {
          _notes = notes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载笔记列表失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentId = widget.editorState.noteId;

    return Drawer(
      width: 280,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.article, size: 20),
                  SizedBox(width: 8),
                  const Text(
                    '笔记列表',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.add, size: 20),
                    onPressed: () async {
                      await widget.editorState.createNewNote();
                      await _loadNotes();
                      if (context.mounted) Navigator.pop(context);
                    },
                    tooltip: '新建笔记',
                  ),
                ],
              ),
            ),
            // 笔记列表
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _notes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.note_add, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              SizedBox(height: 12),
                              Text('暂无笔记', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          itemCount: _notes.length,
                          itemBuilder: (context, index) {
                            final note = _notes[index];
                            final isCurrent = note.id == currentId;
                            return Dismissible(
                              key: ValueKey(note.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onSurface),
                              ),
                              confirmDismiss: (_) async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('删除笔记'),
                                    content: Text('确定要删除「${note.title}」吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Theme.of(context).colorScheme.error,
                                          side: BorderSide(color: Theme.of(context).colorScheme.error),
                                        ),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  setState(() {
                                    _notes.removeWhere((n) => n.id == note.id);
                                  });
                                  await widget.editorState.deleteNote(note.id);
                                  return true;
                                }
                                return false;
                              },
                              onDismissed: (_) {},
                              child: _NoteListTile(
                                note: note,
                                isCurrent: isCurrent,
                                onTap: () async {
                                  await widget.editorState.switchNote(note.id);
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  final NoteInfo note;
  final bool isCurrent;
  final VoidCallback onTap;

  const _NoteListTile({
    required this.note,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.article_outlined,
          size: 20,
          color: isCurrent ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isCurrent ? FontWeight.w600 : null,
            color: isCurrent ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${note.blockCount} 块',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
