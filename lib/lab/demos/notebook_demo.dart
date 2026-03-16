import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../lab_container.dart';
import '../models/lab_note.dart';
import '../providers/lab_note_provider.dart';

/// 笔记本 Demo
class NotebookDemo extends DemoPage {
  @override
  String get title => '笔记本';

  @override
  String get description => 'Markdown 笔记应用，支持实时预览';

  @override
  Widget buildPage(BuildContext context) {
    return const _NotebookDemoPage();
  }
}

class _NotebookDemoPage extends StatefulWidget {
  const _NotebookDemoPage();

  @override
  State<_NotebookDemoPage> createState() => _NotebookDemoPageState();
}

class _NotebookDemoPageState extends State<_NotebookDemoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LabNoteProvider>().loadNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Stack(
        children: [
          Consumer<LabNoteProvider>(
            builder: (context, provider, child) {
              if (provider.notes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.note_alt_outlined, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('暂无笔记', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _createNote(context),
                        icon: const Icon(Icons.add),
                        label: const Text('创建笔记'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                itemCount: provider.notes.length,
                itemBuilder: (context, index) => _NoteCard(
                  note: provider.notes[index],
                  onTap: () => _editNote(context, provider.notes[index]),
                  onDelete: () => _deleteNote(context, provider.notes[index]),
                ),
              );
            },
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () => _createNote(context),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  void _createNote(BuildContext context) async {
    final provider = context.read<LabNoteProvider>();
    final note = await provider.createNote();
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => _NoteEditorPage(noteId: note.id)));
    }
  }

  void _editNote(BuildContext context, LabNote note) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => _NoteEditorPage(noteId: note.id)));
  }

  void _deleteNote(BuildContext context, LabNote note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定删除 "${note.title}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              context.read<LabNoteProvider>().deleteNote(note.id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final LabNote note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteCard({required this.note, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MM月dd日 HH:mm');

    Color cardColor = Colors.white;
    try {
      if (note.color != null && note.color!.startsWith('#')) {
        cardColor = Color(int.parse(note.color!.replaceFirst('#', '0xFF')));
      }
    } catch (e) {}

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: cardColor.withOpacity(0.3)),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(note.title.isEmpty ? '无标题' : note.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) { if (v == 'delete') onDelete(); },
                    itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('删除'))],
                  ),
                ],
              ),
              if (note.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(note.content.length > 100 ? '${note.content.substring(0, 100)}...' : note.content,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                )
              else
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('暂无内容', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontStyle: FontStyle.italic))),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.access_time, size: 12, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(dateFormat.format(note.updatedAt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditorPage extends StatefulWidget {
  final String noteId;
  const _NoteEditorPage({required this.noteId});

  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  bool _isPreview = false;
  bool _hasChanges = false;

  final List<String> _colors = ['#FFFFFF', '#FFEBEE', '#E3F2FD', '#E8F5E9', '#FFF3E0', '#F3E5F5', '#FFFDE7', '#ECEFF1'];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final note = context.read<LabNoteProvider>().getNoteById(widget.noteId);
      if (note != null) {
        _titleController.text = note.title == '新笔记' ? '' : note.title;
        _contentController.text = note.content;
      }
    });

    _titleController.addListener(() => setState(() => _hasChanges = true));
    _contentController.addListener(() => setState(() => _hasChanges = true));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<LabNoteProvider>().updateNote(
      id: widget.noteId,
      title: _titleController.text.isEmpty ? '新笔记' : _titleController.text,
      content: _contentController.text,
    );
    _hasChanges = false;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  void _showColorPicker() {
    final provider = context.read<LabNoteProvider>();
    final note = provider.getNoteById(widget.noteId);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('选择颜色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            Wrap(spacing: 12, runSpacing: 12, children: _colors.map((c) {
              final isSelected = note?.color == c;
              return GestureDetector(
                onTap: () { provider.updateNote(id: widget.noteId, color: c); Navigator.pop(ctx); },
                child: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300, width: isSelected ? 3 : 1),
                  ),
                  child: isSelected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                ),
              );
            }).toList()),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑笔记'),
        actions: [
          IconButton(icon: Icon(_isPreview ? Icons.edit : Icons.preview), onPressed: () => setState(() => _isPreview = !_isPreview)),
          IconButton(icon: const Icon(Icons.palette), onPressed: _showColorPicker),
          IconButton(icon: const Icon(Icons.save), onPressed: _hasChanges ? _save : null),
        ],
      ),
      body: _isPreview ? _buildPreview() : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: TextField(controller: _titleController, decoration: const InputDecoration(hintText: '标题', border: InputBorder.none), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), maxLines: 1)),
        const Divider(),
        Expanded(child: Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _contentController, decoration: const InputDecoration(hintText: '开始写笔记...', border: InputBorder.none), style: theme.textTheme.bodyMedium, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top))),
      ],
    );
  }

  Widget _buildPreview() {
    final theme = Theme.of(context);
    final content = _contentController.text;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_titleController.text.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_titleController.text, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
          if (content.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('暂无内容', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline))))
          else MarkdownBody(data: content, styleSheet: MarkdownStyleSheet(p: theme.textTheme.bodyLarge?.copyWith(height: 1.6)), selectable: true),
        ],
      ),
    );
  }
}

void registerNotebookDemo() {
  demoRegistry.register(NotebookDemo());
}
