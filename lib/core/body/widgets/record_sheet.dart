import 'package:flutter/material.dart';
import '../models/body_region.dart';
import '../models/body_record.dart';
import '../models/body_record_repo.dart';

class RecordSheet extends StatefulWidget {
  final BlockRegion bodyPart;

  const RecordSheet({super.key, required this.bodyPart});

  @override
  State<RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<RecordSheet> {
  final _ctrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  double _pain = 0;
  List<BodyRecord> _history = [];
  List<BodyRecord> _filtered = [];
  String _searchQuery = '';
  BodyRecord? _editing;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchCtrl.text.trim().toLowerCase();
      _applyFilter();
    });
  }

  void _load() {
    setState(() {
      _history = bodyRecordRepo.getRecords(widget.bodyPart.id);
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filtered = _history;
    } else {
      _filtered = _history
          .where((r) => r.content.toLowerCase().contains(_searchQuery))
          .toList();
    }
  }

  Color get _painColor =>
      Color.lerp(Colors.green, Colors.red, _pain / 10) ?? Colors.grey;

  void _startEdit(BodyRecord record) {
    setState(() {
      _editing = record;
      _ctrl.text = record.content;
      _pain = (record.painLevel ?? 0).toDouble();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _ctrl.clear();
      _pain = 0;
    });
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    if (_editing != null) {
      // 编辑模式：删旧的，加新的
      await bodyRecordRepo.remove(_editing!);
      await bodyRecordRepo.add(
        widget.bodyPart.id,
        text,
        _pain.round(),
      );
      setState(() => _editing = null);
    } else {
      await bodyRecordRepo.add(
        widget.bodyPart.id,
        text,
        _pain.round(),
      );
    }
    _ctrl.clear();
    _pain = 0;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          children: [
            // 标题栏
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: tissueColors[widget.bodyPart.tissue],
                    shape: widget.bodyPart.shape == BlockShape.circle
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    borderRadius: widget.bodyPart.shape != BlockShape.circle
                        ? BorderRadius.circular(3)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.bodyPart.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 8),
                Text(
                  tissueLabels[widget.bodyPart.tissue]!,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 不适程度滑块
            Row(
              children: [
                const Text('不适程度'),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _painColor,
                      thumbColor: _painColor,
                    ),
                    child: Slider(
                      value: _pain,
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: _pain.round().toString(),
                      onChanged: (v) => setState(() => _pain = v),
                    ),
                  ),
                ),
                Text(
                  '${_pain.round()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _painColor,
                  ),
                ),
              ],
            ),
            // 输入框
            TextField(
              controller: _ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: _editing != null ? '编辑记录...' : '描述你的感受...',
                border: const OutlineInputBorder(),
                suffixIcon: _editing != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _cancelEdit,
                        tooltip: '取消编辑',
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: Icon(_editing != null ? Icons.check : Icons.save),
              label: Text(_editing != null ? '更新' : '保存'),
              onPressed: _save,
            ),
            const Divider(height: 32),
            // 搜索 + 历史记录
            Row(
              children: [
                Text(
                  '历史记录 (${_history.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (_history.length > 3) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索记录...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ..._filtered.map(
              (r) => _RecordTile(
                record: r,
                isEditing: _editing?.key == r.key,
                onEdit: () => _startEdit(r),
                onDelete: () async {
                  await bodyRecordRepo.remove(r);
                  if (_editing?.key == r.key) _cancelEdit();
                  _load();
                },
              ),
            ),
            if (_filtered.isEmpty && _searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '没有找到匹配的记录',
                  style: TextStyle(color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final BodyRecord record;
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RecordTile({
    required this.record,
    required this.isEditing,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final painColor = Color.lerp(
      Colors.green,
      Colors.red,
      (record.painLevel ?? 0) / 10,
    );

    return Dismissible(
      key: ValueKey(record.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        title: Text(record.content),
        subtitle: Text(
          '${record.createdAt.toLocal().toString().substring(0, 16)}'
          ' · 不适: ${record.painLevel ?? "-"}/10',
        ),
        dense: true,
        leading: Icon(Icons.circle, size: 10, color: painColor),
        trailing: isEditing
            ? const Icon(Icons.edit, size: 16, color: Colors.blue)
            : IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
                tooltip: '编辑',
                visualDensity: VisualDensity.compact,
              ),
        onTap: onEdit,
      ),
    );
  }
}
