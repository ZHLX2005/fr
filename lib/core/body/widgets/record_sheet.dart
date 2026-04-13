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
  double _pain = 0;
  List<BodyRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _history = bodyRecordRepo.getRecords(widget.bodyPart.id);
    });
  }

  Color get _painColor =>
      Color.lerp(Colors.green, Colors.red, _pain / 10) ?? Colors.grey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                Text(widget.bodyPart.label,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                Text(tissueLabels[widget.bodyPart.tissue]!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
              decoration: const InputDecoration(
                hintText: '描述你的感受...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('保存'),
              onPressed: () async {
                if (_ctrl.text.trim().isEmpty) return;
                await bodyRecordRepo.add(
                  widget.bodyPart.id,
                  _ctrl.text.trim(),
                  _pain.round(),
                );
                _ctrl.clear();
                _load();
              },
            ),
            const Divider(height: 32),
            Text('历史记录 (${_history.length})',
                style: Theme.of(context).textTheme.titleMedium),
            ..._history.map((r) => Dismissible(
                  key: ValueKey(r.key),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await bodyRecordRepo.remove(r);
                    _load();
                  },
                  child: ListTile(
                    title: Text(r.content),
                    subtitle: Text(
                      '${r.createdAt.toLocal().toString().substring(0, 16)}'
                      ' · 不适: ${r.painLevel ?? "-"}/10',
                    ),
                    dense: true,
                    leading: Icon(
                      Icons.circle,
                      size: 10,
                      color: Color.lerp(
                          Colors.green, Colors.red, (r.painLevel ?? 0) / 10),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
