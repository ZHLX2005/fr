import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock_record.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/clock_editor_sheet.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

/// Clocks tab — grid of clock cards + records list.
/// Preserves the core clock functionality (start/pause/reset, swipe-rename,
/// create-clock-from-record). The wave divider from the old design is gone;
/// the records list is shown below the grid.
///
/// Note: this widget returns its content as plain widgets (no inner Scaffold
/// or FAB). The shell at `clock_demo.dart` owns the single Scaffold/FAB and
/// calls [openEditor] when the FAB is tapped. This avoids the IndexedStack +
/// nested-Scaffold hit-testing trap that previously broke CRUD after a track
/// was defined.
class ClocksTab extends StatefulWidget {
  /// Optional callback invoked when the State mounts so the parent shell can
  /// call our [openEditor] from its FAB. This avoids the IndexedStack +
  /// nested-Scaffold hit-testing trap that previously broke CRUD after a track
  /// was defined.
  final void Function(Future<void> Function(BuildContext) openEditor)? onReady;
  const ClocksTab({super.key, this.onReady});

  @override
  State<ClocksTab> createState() => _ClocksTabState();
}

class _ClocksTabState extends State<ClocksTab> {
  @override
  void initState() {
    super.initState();
    // Publish our openEditor to the shell after the first frame so the
    // shell's `context` is available for the FAB callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady?.call(_openEditor);
    });
  }

  /// Called by the shell's FAB when the user is on the Clocks tab.
  Future<void> _openEditor(BuildContext context) async {
    final provider = context.read<LabClockProvider>();
    final result = await showClockEditor(context);
    if (result == null) return;
    await provider.createClock(
      title: result.title,
      description: result.description,
      durationSeconds: result.durationSeconds,
      color: result.color,
    );
    // setBeat is on the *newest* clock (inserted at index 0)
    final newest = provider.clocks.first;
    await provider.setBeat(
      newest.id,
      bpm: result.bpm,
      beatPattern: result.beatPattern,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LabClockProvider>(
      builder: (context, provider, _) {
        // 空状态进 sliver，Records 区恒渲染——clocks 为空不能吞掉历史记录
        return CustomScrollView(
          slivers: [
            if (provider.clocks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: _EmptyState(onAdd: () => _openEditor(context)),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ClockCard(clock: provider.clocks[i]),
                    childCount: provider.clocks.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('记录', style: ZenText.label),
              ),
            ),
            if (provider.records.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text('暂无记录。', style: ZenText.label),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RecordTile(record: provider.records[i]),
                  childCount: provider.records.length,
                ),
              ),
            // Padding so the last record isn't hidden under the shell's FAB.
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ZenEmptyState(
      icon: Icons.timer_outlined,
      message: '暂无时钟',
      actionLabel: '添加时钟',
      onAction: onAdd,
    );
  }
}

class _ClockCard extends StatelessWidget {
  final LabClock clock;
  const _ClockCard({required this.clock});

  @override
  Widget build(BuildContext context) {
    final p = context.read<LabClockProvider>();
    final baseColor = clock.color == null
        ? Theme.of(context).colorScheme.primary
        : Color(int.parse(clock.color!.replaceFirst('#', '0xFF')));
    final remaining = clock.remainingSeconds;
    final hasBeat = clock.bpm != null;
    final silenced = p.isClockSilenced(clock.id);
    final isActive = clock.isRunning && hasBeat && !silenced;

    return InkWell(
      // Long-press to edit; tap is reserved for the play/pause/reset buttons
      // inside the card (nested InkWells compete in the gesture arena and the
      // outer tap was stealing button taps, so the clock couldn't be stopped).
      onLongPress: () async {
        final result = await showClockEditor(context, existing: clock);
        if (result == null) return;
        await p.updateClock(
          id: clock.id,
          title: result.title,
          description: result.description,
          durationSeconds: result.durationSeconds,
          color: result.color,
        );
        await p.setBeat(
          clock.id,
          bpm: result.bpm,
          beatPattern: result.beatPattern,
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: zenCardTheme(context),
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: baseColor,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    clock.title,
                    style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _confirmDelete(context, p),
                  customBorder: CircleBorder(),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            Spacer(),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatTime(remaining),
                  style: ZenText.monoDigit.copyWith(
                    fontSize: 32,
                    color: remaining < 0
                        ? context.colors.danger
                        : context.colors.text,
                  ),
                ),
              ),
            ),
            Spacer(),
            if (hasBeat)
              Row(
                children: [
                  ZenDot(),
                  SizedBox(width: 6),
                  Text(
                    (() {
                      final modeLabel = clock.beatPattern == '1/4'
                          ? '单拍'
                          : '双拍';
                      return '${clock.bpm}bpm · $modeLabel';
                    })(),
                    style: ZenText.monoDigitSmall,
                  ),
                ],
              ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ZenIconButton(
                  icon: clock.isRunning
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: baseColor,
                  onTap: () => clock.isRunning
                      ? p.pauseCountdown(clock.id)
                      : p.startCountdown(clock.id),
                ),
                SizedBox(width: 12),
                ZenIconButton(
                  icon: Icons.refresh_rounded,
                  color: context.colors.textMuted,
                  onTap: () => p.resetCountdown(clock.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, LabClockProvider p) {
    ZenConfirmDialog.show(
      context: context,
      title: '删除时钟',
      message: '删除"${clock.title}"？',
      onConfirm: () => p.deleteClock(clock.id),
    );
  }
}

class _RecordTile extends StatefulWidget {
  final LabClockRecord record;
  const _RecordTile({required this.record});

  @override
  State<_RecordTile> createState() => _RecordTileState();
}

class _RecordTileState extends State<_RecordTile> {
  // Each tile owns its own swipe offset so multiple tiles don't fight.
  double _offsetX = 0;
  static const double _actionWidth = 80;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.read<LabClockProvider>();
    final record = widget.record;
    final isCompleted = record.completed;
    final color = isCompleted ? context.colors.accent : context.colors.danger;
    final dateStr = formatRecordDate(record.startTime);

    // The card content (slides left on swipe). No margin here — the outer
    // Padding provides horizontal insets so the action buttons behind it align
    // to the same right edge as the card.
    final card = Container(
      decoration: zenCardTheme(context),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCompleted ? Icons.check_rounded : Icons.schedule_rounded,
              color: color,
              size: 22,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () => _rename(context, p),
                  child: Text(
                    record.customTitle ?? record.clockTitle,
                    style: ZenText.body,
                  ),
                ),
                Text(dateStr, style: ZenText.monoDigitSmall),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatDuration(p.getRecordLiveDuration(record)),
              style: ZenText.monoDigitSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    // Ported from original `_RecordSwipeAction` (clock_demo.dart:1396-1570).
    // Swipe left reveals two action buttons (Delete / Create) — no tap-to-sheet.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _offsetX = (_offsetX + details.delta.dx).clamp(
              -_actionWidth * 2,
              0,
            );
          });
        },
        onHorizontalDragEnd: (_) {
          if (_offsetX < -_actionWidth * 0.4) {
            setState(() {
              _offsetX = -_actionWidth * 2;
              _isExpanded = true;
            });
          } else {
            setState(() {
              _offsetX = 0;
              _isExpanded = false;
            });
          }
        },
        onTap: () {
          if (_isExpanded) {
            setState(() {
              _offsetX = 0;
              _isExpanded = false;
            });
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          // Clips both the card and the action buttons to the same 6px
          // rounding as zenCardTheme(context), so sharp-cornered action buttons don't
          // bleed past the card's rounded corners when swiped left.
          child: Stack(
            children: [
              // Action buttons (overflow to the right).
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _actionWidth * 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ZenSwipeAction(
                      label: '删除',
                      icon: Icons.delete_outline,
                      color: context.colors.danger,
                      // Round both left corners so it tucks under the card's
                      // right edge cleanly.
                      leftRounded: true,
                      onTap: () {
                        setState(() {
                          _offsetX = 0;
                          _isExpanded = false;
                        });
                        if (!record.canDelete) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text('运行中或暂停的记录不可删除，请先完成'),
                              ),
                            );
                          return;
                        }
                        p.deleteRecord(record.id);
                      },
                    ),
                    ZenSwipeAction(
                      label: '新建',
                      icon: Icons.add,
                      color: context.colors.accent,
                      leftRounded: false,
                      onTap: () async {
                        setState(() {
                          _offsetX = 0;
                          _isExpanded = false;
                        });
                        final dur = p.getRecordLiveDuration(record);
                        if (dur > 0) {
                          await p.createClock(
                            title: record.customTitle ?? record.clockTitle,
                            durationSeconds: dur,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              // Content layer slides left with the gesture.
              Transform.translate(offset: Offset(_offsetX, 0), child: card),
            ],
          ), // Stack
        ), // ClipRect
      ), // GestureDetector
    ); // Padding
  }

  void _rename(BuildContext context, LabClockProvider p) {
    final record = widget.record;
    final ctl = TextEditingController(
      text: record.customTitle ?? record.clockTitle,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('重命名记录'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '取消',
              style: TextStyle(color: context.colors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              final v = ctl.text.trim();
              if (v.isNotEmpty) p.updateRecordTitle(record.id, v);
              Navigator.pop(ctx);
            },
            child: Text('保存', style: TextStyle(color: context.colors.accent)),
          ),
        ],
      ),
    );
  }
}
