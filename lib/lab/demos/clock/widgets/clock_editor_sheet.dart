import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';
import 'zen_theme.dart';

class ClockEditorResult {
  final String title;
  final String description;
  final int durationSeconds;
  final String color;
  final int? bpm;
  final String? beatPattern;

  ClockEditorResult({
    required this.title,
    required this.description,
    required this.durationSeconds,
    required this.color,
    this.bpm,
    this.beatPattern,
  });
}

const _palette = [
  '#D4644B', '#7A9A7E', '#5B7A8C', '#C9A86A',
  '#A2808E', '#C7B299', '#5A544B', '#2C2C2C',
];

Future<ClockEditorResult?> showClockEditor(BuildContext context, {LabClock? existing}) {
  return showModalBottomSheet<ClockEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ZenColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ClockEditorSheet(existing: existing),
  );
}

class _ClockEditorSheet extends StatefulWidget {
  final LabClock? existing;
  const _ClockEditorSheet({this.existing});
  @override
  State<_ClockEditorSheet> createState() => _ClockEditorSheetState();
}

class _ClockEditorSheetState extends State<_ClockEditorSheet> {
  late TextEditingController _titleCtl;
  late TextEditingController _descCtl;
  late int _hours, _minutes, _seconds;
  late String _color;
  late bool _beatEnabled;
  late int _bpm;
  late String? _beatPattern;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _titleCtl = TextEditingController(text: c?.title ?? '');
    _descCtl = TextEditingController(text: c?.description ?? '');
    final total = c?.durationSeconds ?? 300;
    _hours = total ~/ 3600;
    _minutes = (total % 3600) ~/ 60;
    _seconds = total % 60;
    _color = c?.color ?? _palette.first;
    _beatEnabled = c?.bpm != null;
    _bpm = c?.bpm ?? 60;
    _beatPattern = c?.beatPattern ?? '4/4';
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(
              color: ZenColors.hair, borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(widget.existing == null ? 'Add clock' : 'Edit clock', style: ZenText.title)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                iconSize: 24,
                color: ZenColors.ink,
                tooltip: 'Cancel',
              ),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtl,
              style: ZenText.body,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtl,
              style: ZenText.body,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Duration', style: ZenText.label),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WheelPicker(label: 'h', value: _hours, max: 23, onChanged: (v) => setState(() => _hours = v)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: ZenText.title)),
                _WheelPicker(label: 'm', value: _minutes, max: 59, onChanged: (v) => setState(() => _minutes = v)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: ZenText.title)),
                _WheelPicker(label: 's', value: _seconds, max: 59, onChanged: (v) => setState(() => _seconds = v)),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Color', style: ZenText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _palette.map((c) {
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                      border: selected ? Border.all(color: ZenColors.ink, width: 3) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Beat section
            Row(children: [
              const Expanded(child: Text('Beat', style: ZenText.label)),
              Switch(
                value: _beatEnabled,
                activeThumbColor: ZenColors.sage,
                onChanged: (v) => setState(() => _beatEnabled = v),
              ),
            ]),
            if (_beatEnabled) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Text('BPM', style: ZenText.label),
                const Spacer(),
                IconButton(
                  onPressed: _bpm > 20 ? () => setState(() => _bpm -= 5) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 64,
                  child: Text('$_bpm', textAlign: TextAlign.center, style: ZenText.monoDigitSmall.copyWith(color: ZenColors.ink, fontSize: 20)),
                ),
                IconButton(
                  onPressed: _bpm < 300 ? () => setState(() => _bpm += 5) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: 8),
              // MetronomePresets.patterns is List<BeatPattern> (not a Map), so iterate by .name.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MetronomePresets.patterns.map((p) {
                  final key = p.name;
                  final selected = key == _beatPattern;
                  return GestureDetector(
                    onTap: () => setState(() => _beatPattern = key),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? ZenColors.sage : ZenColors.surface,
                        border: Border.all(color: selected ? ZenColors.sage : ZenColors.hair),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(key, style: ZenText.button.copyWith(
                        color: selected ? Colors.white : ZenColors.ink,
                      )),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context, ClockEditorResult(
                    title: _titleCtl.text.isEmpty ? 'New clock' : _titleCtl.text,
                    description: _descCtl.text,
                    durationSeconds: _hours * 3600 + _minutes * 60 + _seconds,
                    color: _color,
                    bpm: _beatEnabled ? _bpm : null,
                    beatPattern: _beatEnabled ? _beatPattern : null,
                  ));
                },
                style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
                child: Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelPicker extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  const _WheelPicker({required this.label, required this.value, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 120,
      child: ListWheelScrollView.useDelegate(
        itemExtent: 40,
        physics: const FixedExtentScrollPhysics(),
        controller: FixedExtentScrollController(initialItem: value),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max + 1,
          builder: (_, i) => Center(
            child: Text(
              i.toString().padLeft(2, '0'),
              style: ZenText.monoDigitSmall.copyWith(
                fontSize: i == value ? 24 : 16,
                color: i == value ? ZenColors.ink : ZenColors.secondary,
                fontWeight: i == value ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
