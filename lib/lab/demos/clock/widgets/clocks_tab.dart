import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/const_clock_max_mode.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock_record.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/utils/clock_chain_util.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/widgets/clock_editor_sheet.dart';
import 'package:xiaodouzi_fr/core/theme/component/zen/zen_theme.dart';

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
  /// max 模式：按 `LabClock.parentId` 的血缘链合并 —— clock 网格里一条链合并成
  /// 一张卡（中央取链上最大时长），记录区一条链折叠成一行。
  ///
  /// UI 局部状态，不持久化；关闭后回到全量列表，无数据丢失。
  ///
  /// 已知不一致（**不要当 bug 修**）：桌面小组件的 `_syncToWidget` /
  /// `toggleLatestClock` 锚定 `provider.clocks.first`，而合并卡代表的是"链上
  /// 时长最大者"。例如 `C1(60min) ← C2(30min)` 时桌面 widget 显示/切换 C2，
  /// 合并卡显示 C1。`_clocks.first` 是 fr #5 明确记录的 widget 契约，且 max 模式
  /// 本身就是不持久化的 UI 透镜，widget 看不到它。
  bool _maxMode = false;

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
    // FAB 新建：没有来源 clock → "新的根时钟"开关不显示，新 clock 恒为新根。
    final result = await showClockEditor(context);
    if (result == null) return;
    final created = await provider.createClock(
      title: result.title,
      description: result.description,
      durationSeconds: result.durationSeconds,
      color: result.color,
    );
    // 用 createClock 的返回值定位新 clock，而不是 provider.clocks.first ——
    // 后者依赖 "insert(0) ⇒ first 是最新" 这个隐式契约。
    await provider.setBeat(
      created.id,
      bpm: result.bpm,
      beatPattern: result.beatPattern,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LabClockProvider>(
      builder: (context, provider, _) {
        // max 模式下网格按血缘链合并：一条链一张卡。非 max 模式不计算（空列表）。
        final chains = _maxMode ? provider.clockChains : const <ClockChain>[];
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
                    (context, i) => _maxMode
                        ? _ClockCard(
                            clock: chains[i].representative,
                            chain: chains[i],
                          )
                        : _ClockCard(clock: provider.clocks[i]),
                    childCount: _maxMode
                        ? chains.length
                        : provider.clocks.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('记录', style: ZenText.label),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        kClockMaxModeHint,
                        style: ZenText.monoDigitSmall.copyWith(
                          color: context.colors.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      kClockMaxModeLabel,
                      style: ZenText.monoDigitSmall.copyWith(
                        color: _maxMode
                            ? context.colors.accent
                            : context.colors.textMuted,
                      ),
                    ),
                    SizedBox(width: 4),
                    Switch(
                      value: _maxMode,
                      onChanged: (v) => setState(() => _maxMode = v),
                    ),
                  ],
                ),
              ),
            ),
            if (provider.records.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text('暂无记录。', style: ZenText.label),
                ),
              )
            else if (_maxMode)
              () {
                final rows = provider.chainRecordRows;
                if (rows.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(kClockMaxModeEmpty, style: ZenText.label),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ChainRecordTile(row: rows[i]),
                    childCount: rows.length,
                  ),
                );
              }()
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

  /// 非空 = max 模式下的**合并卡**：一张卡代表整条 parent 链。
  /// [clock] 此时是链上代表（时长最大者，或运行中的成员）。
  final ClockChain? chain;

  const _ClockCard({required this.clock, this.chain});

  @override
  Widget build(BuildContext context) {
    final p = context.read<LabClockProvider>();
    // 合并卡：标题与圆点取**链根**（稳定，不随代表漂移）；
    // 运行态、节拍、按钮、长按编辑全部作用于**代表** clock。
    final display = chain?.representative ?? clock;
    final titleClock = chain?.root ?? clock;
    final baseColor = titleClock.color == null
        ? Theme.of(context).colorScheme.primary
        : Color(int.parse(titleClock.color!.replaceFirst('#', '0xFF')));
    final remaining = display.remainingSeconds;

    // 合并卡空闲时中央显示"链上最长目标时长"，运行中维持实时倒计时
    // （不让静态最大值盖掉进度感），此时最大值退到角标行。
    final centerSeconds = chain?.centerSeconds ?? remaining;
    final isMaxDisplay = chain?.centerIsChainMax ?? false;
    final hasBeat = display.bpm != null;

    return InkWell(
      // Long-press to edit; tap is reserved for the play/pause/reset buttons
      // inside the card (nested InkWells compete in the gesture arena and the
      // outer tap was stealing button taps, so the clock couldn't be stopped).
      onLongPress: () async {
        final result = await showClockEditor(context, existing: display);
        if (result == null) return;
        await p.updateClock(
          id: display.id,
          title: result.title,
          description: result.description,
          durationSeconds: result.durationSeconds,
          color: result.color,
          // 开关可见时才可能为 true；不可见时恒 false → 无副作用。
          // true = 打开"新的根时钟" → 脱离链成为新根。
          clearParent: result.isNewRoot,
        );
        await p.setBeat(
          display.id,
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
                    titleClock.title,
                    style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 合并卡不提供 × 删除：一张卡代表整条链，"删哪一台"语义模糊，
                // 要删就关掉 max 开关回普通模式删。
                if (chain == null)
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
                  )
                else if (chain!.size > 1)
                  Text(
                    clockChainSizeLabel(chain!.size),
                    style: ZenText.monoDigitSmall.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
              ],
            ),
            Spacer(),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatTime(centerSeconds),
                  style: ZenText.monoDigit.copyWith(
                    fontSize: 32,
                    color: isMaxDisplay
                        ? context.colors.accent
                        : (remaining < 0
                            ? context.colors.danger
                            : context.colors.text),
                  ),
                ),
              ),
            ),
            // 合并卡角标：空闲 = "链上最长"；运行中 = "链上最长 03:00"
            // （把刚被实时倒计时顶下去的最大值挪到这里，信息不丢）。
            if (chain != null) ...[
              SizedBox(height: 2),
              Center(
                child: Text(
                  chain!.centerIsChainMax
                      ? kClockChainMaxBadge
                      : '$kClockChainMaxBadge ${formatTime(chain!.maxDurationSeconds)}',
                  style: ZenText.monoDigitSmall.copyWith(
                    color: context.colors.accent,
                  ),
                ),
              ),
            ],
            Spacer(),
            if (hasBeat)
              Row(
                children: [
                  ZenDot(),
                  SizedBox(width: 6),
                  Text(
                    (() {
                      final modeLabel = display.beatPattern == '1/4'
                          ? '单拍'
                          : '双拍';
                      return '${display.bpm}bpm · $modeLabel';
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
                  icon: display.isRunning
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: baseColor,
                  onTap: () => display.isRunning
                      ? p.pauseCountdown(display.id)
                      : p.startCountdown(display.id),
                ),
                SizedBox(width: 12),
                ZenIconButton(
                  icon: Icons.refresh_rounded,
                  color: context.colors.textMuted,
                  onTap: () => p.resetCountdown(display.id),
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
                        if (dur <= 0) return;
                        // 来源 clock 可能已被删除 → 开关不显示，新 clock 恒为新根。
                        final source = p.getClockById(record.clockId);
                        // 打开预填编辑器而不是一步创建：用户可当场把时长调长
                        // （这正是血缘链上 maxDurationSeconds 递增的来源），
                        // 并用"新的根时钟"开关决定并入来源链还是另起一条。
                        final result = await showClockEditor(
                          context,
                          seed: ClockEditorSeed(
                            title: record.customTitle ?? record.clockTitle,
                            durationSeconds: dur,
                            color: LabClockProvider.resolveColor(source?.color),
                            bpm: source?.bpm,
                            beatPattern: source?.beatPattern,
                          ),
                          mergeParent: source,
                        );
                        if (result == null || !mounted) return;
                        final created = await p.createClock(
                          title: result.title,
                          description: result.description,
                          durationSeconds: result.durationSeconds,
                          color: result.color,
                          parentId: ClockChainUtil.resolveParentId(
                            mergeParent: source,
                            isNewRoot: result.isNewRoot,
                          ),
                        );
                        await p.setBeat(
                          created.id,
                          bpm: result.bpm,
                          beatPattern: result.beatPattern,
                        );
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

/// max 模式下按**血缘链**折叠后的单行。
///
/// 角标 = 该链记录条数，右侧 = 链内**实际时长**最大的那条（不是配置时长）。
/// 不带 swipe/重命名/删除 —— 折叠视图是"只读"的概览面板，操作回到普通模式。
class _ChainRecordTile extends StatelessWidget {
  final ChainRecordRow row;
  const _ChainRecordTile({required this.row});

  @override
  Widget build(BuildContext context) {
    // 孤儿行（所属 clock 已删）用 textMuted 弱化，视觉上和活跃链区分开。
    final accent = row.isOrphan
        ? context.colors.textMuted
        : context.colors.accent;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: zenCardTheme(context),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                clockRecordCountLabel(row.count),
                style: ZenText.monoDigitSmall.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title, style: ZenText.body),
                  Text(
                    formatRecordDate(row.record.startTime),
                    style: ZenText.monoDigitSmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                formatTime(row.actualSeconds),
                style: ZenText.monoDigitSmall.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
