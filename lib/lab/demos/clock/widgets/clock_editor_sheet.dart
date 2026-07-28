import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
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
  late TextEditingController _roundsCtl;
  late int _hours, _minutes, _seconds;
  late String _color;
  late bool _beatEnabled;
  /// '1beat' = one beat per round (all strong); '2beat' = two beats per round (strong-weak).
  late String _mode;

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
    // Reverse-derive rounds/mode from stored bpm+pattern when editing.
    // 1beat mode stores pattern '1/4' (1 beat/round); 2beat stores '2/4' (2 beats/round).
    final pattern = c?.beatPattern;
    if (pattern == '1/4') {
      _mode = '1beat';
    } else {
      _mode = '2beat'; // default and for '2/4'
    }
    final beatsPerRound = _mode == '1beat' ? 1 : 2;
    final duration = c?.durationSeconds ?? 300;
    final bpm = c?.bpm ?? 40;
    // rounds = bpm * duration / 60 / beatsPerRound
    final derivedRounds = (bpm * duration / 60 / beatsPerRound).round();
    _roundsCtl = TextEditingController(text: derivedRounds > 0 ? '$derivedRounds' : '40');
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    _roundsCtl.dispose();
    super.dispose();
  }

  /// Total duration in seconds from the wheel pickers.
  int get _durationSeconds => _hours * 3600 + _minutes * 60 + _seconds;

  /// Parsed round count (defensive: empty/garbage → 0).
  int get _rounds => int.tryParse(_roundsCtl.text.trim()) ?? 0;

  /// beatsPerRound for the current mode.
  int get _beatsPerRound => _mode == '1beat' ? 1 : 2;

  /// Auto-computed BPM from rounds + mode + duration.
  /// bpm = rounds * beatsPerRound * 60 / durationSeconds
  int? get _computedBpm {
    final rounds = _rounds;
    final dur = _durationSeconds;
    if (rounds <= 0 || dur <= 0) return null;
    final bpm = (rounds * _beatsPerRound * 60 / dur).round();
    if (bpm < 20 || bpm > 300) return null;
    return bpm;
  }

  /// Auto-computed beat pattern name for the current mode.
  String get _computedPattern => _mode == '1beat' ? '1/4' : '2/4';

  /// Human-readable preview line.
  String get _preview {
    final bpm = _computedBpm;
    if (bpm == null) return 'Enter rounds and duration';
    final secondsPerBeat = (_durationSeconds / (_rounds * _beatsPerRound)).toStringAsFixed(1);
    final rhythm = _mode == '1beat' ? 'all strong' : 'strong-weak';
    return '$_rounds rounds · $bpm BPM · ${secondsPerBeat}s/beat · $rhythm';
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
            // Beat section: rounds + mode → auto-computed bpm/pattern.
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
              // Total rounds input.
              TextField(
                controller: _roundsCtl,
                keyboardType: TextInputType.number,
                style: ZenText.body,
                decoration: const InputDecoration(
                  labelText: 'Total rounds',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              // Mode toggle: 1beat (all strong) vs 2beat (strong-weak).
              const Text('Mode', style: ZenText.label),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _ModeChip(
                    label: '1 beat / round',
                    sub: 'all strong (inhale)',
                    selected: _mode == '1beat',
                    onTap: () => setState(() => _mode = '1beat'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeChip(
                    label: '2 beats / round',
                    sub: 'strong-weak (inhale-exhale)',
                    selected: _mode == '2beat',
                    onTap: () => setState(() => _mode = '2beat'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // Live preview.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: zenCard(),
                child: Text(_preview, style: ZenText.monoDigitSmall.copyWith(
                  color: _computedBpm == null ? ZenColors.mutedRed : ZenColors.ink,
                  fontSize: 13,
                )),
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
                    durationSeconds: _durationSeconds,
                    color: _color,
                    bpm: _beatEnabled ? _computedBpm : null,
                    beatPattern: _beatEnabled ? _computedPattern : null,
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

/// Mode selector chip for the Beat section (1beat / 2beat).
class _ModeChip extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ZenColors.sage : ZenColors.surface,
          border: Border.all(color: selected ? ZenColors.sage : ZenColors.hair),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ZenText.button.copyWith(
              color: selected ? Colors.white : ZenColors.ink,
              fontSize: 14,
            )),
            const SizedBox(height: 2),
            Text(sub, style: ZenText.monoDigitSmall.copyWith(
              color: selected ? Colors.white.withValues(alpha: 0.85) : ZenColors.secondary,
              fontSize: 11,
            )),
          ],
        ),
      ),
    );
  }
}
