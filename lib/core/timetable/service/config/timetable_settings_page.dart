import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../domain/models.dart';
import '../../presentation/timetable_store.dart';
import 'anime_dsl_generator.dart';
import 'anime_source_adapter.dart';
import 'timetable_anime_editor_page.dart';
import 'sicau_import_dialog.dart';
import 'timetable_anime_import_dialog.dart';
import 'timetable_import_dialog.dart';
import 'timetable_week_calculator.dart';
import '../../../../widgets/theme/zen_theme.dart';

/// 课表设置页 —— 沿用 Zen 设计系统组件（zenCard/ZenSection/zenButton）。
/// 课表主页面（timetable_page）使用 TimetableColors 自己的配色保持稳定，不动。
class TimetableSettingsPage extends ConsumerStatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  ConsumerState<TimetableSettingsPage> createState() =>
      _TimetableSettingsPageState();
}

class _TimetableSettingsPageState
    extends ConsumerState<TimetableSettingsPage> {
  late final TextEditingController _startDateController;
  late int _cycleCount;
  late int _daysPerCycle;
  late int _slotsPerDay;
  late bool _isSchoolMode;
  late bool _isAnimeMode;
  late int _leftLabelMode;
  late double _leftWidth;
  late int _slotDurationMin;
  late List<String> _slotLabels;
  late List<String> _slotStartTimes;

  @override
  void initState() {
    super.initState();
    final config = ref.read(TimetableStore.provider).config;
    _startDateController = TextEditingController(text: config.startDateIso);
    _cycleCount = config.cycleCount;
    _daysPerCycle = config.daysPerCycle;
    _slotsPerDay = config.slotsPerDay;
    _isSchoolMode = config.isSchoolMode;
    _isAnimeMode = config.isAnimeMode;
    _leftLabelMode = config.leftLabelMode;
    _leftWidth = config.leftWidth;
    _slotDurationMin = config.slotDurationMin;
    _slotLabels = List<String>.from(config.slotLabels ?? const []);
    _slotStartTimes = List<String>.from(config.slotStartTimes ?? const []);
    _ensureSlotLists();
  }

  /// 保持标签/时间列表长度与 slotsPerDay 对齐（缺位补空串）
  void _ensureSlotLists() {
    if (_slotLabels.length != _slotsPerDay) {
      _slotLabels = List.generate(
        _slotsPerDay,
        (i) => i < _slotLabels.length ? _slotLabels[i] : '',
      );
    }
    if (_slotStartTimes.length != _slotsPerDay) {
      _slotStartTimes = List.generate(
        _slotsPerDay,
        (i) => i < _slotStartTimes.length ? _slotStartTimes[i] : '',
      );
    }
  }

  /// 去掉列表尾部的空串（保存时 null 语义：无数据）
  List<String>? _trimmedOrNull(List<String> list) {
    final trimmed = List<String>.from(list);
    while (trimmed.isNotEmpty && trimmed.last.trim().isEmpty) {
      trimmed.removeLast();
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void dispose() {
    _startDateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(TimetableStore.provider.notifier);

    // 通用模式原样保存；学校模式回退到最近周一（fr #2）
    final rawStart = _startDateController.text.trim();
    final startDateIso = resolveStartDateIso(
      rawStart,
      isSchoolMode: _isSchoolMode,
    );
    if (startDateIso != rawStart) {
      _startDateController.text = startDateIso;
    }

    // 学校模式下强制 daysPerCycle = 7
    final daysToSave = _isSchoolMode ? 7 : _daysPerCycle;

    _ensureSlotLists();
    final error = await store.updateConfig(
      startDateIso: startDateIso,
      cycleCount: _cycleCount,
      daysPerCycle: daysToSave,
      slotsPerDay: _slotsPerDay,
      isSchoolMode: _isSchoolMode,
      isAnimeMode: _isAnimeMode,
      leftLabelMode: _leftLabelMode,
      leftWidth: _leftWidth,
      slotDurationMin: _slotDurationMin,
      slotLabels: _trimmedOrNull(_slotLabels),
      slotStartTimes: _trimmedOrNull(_slotStartTimes),
    );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('设置已保存（起始日期 $startDateIso）')));
      Navigator.pop(context);
    }
  }

  Future<void> _openImport() async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => const TimetableImportDialog(),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 门课程')));
    }
  }

  Future<void> _openSicauImport() async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => const SicauImportDialog(),
    );
    if (count != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已从教务系统导入 $count 门课程')));
    }
  }

  /// 打开垂直排期编辑页（纯剧语言配置，自动重算 DSL）
  Future<void> _openAnimeEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TimetableAnimeEditorPage()),
    );
  }

  /// 从开放 API 导入番剧 → 填充草稿后直接进入排期编辑
  Future<void> _openAnimeImport() async {
    final drafts = await showDialog<List<AnimeDraft>>(
      context: context,
      builder: (_) => const TimetableAnimeImportDialog(),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    final initial = drafts
        .map(
          (d) => AnimeSeriesDraft(
            title: d.title,
            startDateIso: d.startDateIso ?? '',
            weekday: d.weekday ?? 1,
            time: d.time ?? '',
            episodes: d.episodes ?? 13,
          ),
        )
        .toList();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimetableAnimeEditorPage(initialSeries: initial),
      ),
    );
  }

  Future<void> _exportDsl() async {
    final dsl = ref.read(TimetableStore.provider.notifier).exportToDsl();
    if (dsl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无课程可导出')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: dsl));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DSL 已复制到剪贴板')));
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空确认'),
        content: const Text('确定要清空所有课程吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ZenColors.mutedRed),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(TimetableStore.provider.notifier).clearAllItems();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清空所有课程')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return zenPageScaffold(
      title: '时间配置',
      actions: [
        IconButton(
          icon: const Icon(Icons.save),
          tooltip: '保存',
          onPressed: _save,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 模式选择 ──
          ZenSection(
            title: '课表模式',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeSelector(),
                if (_isSchoolMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    '学校模式：周一为起始日期，7天固定，支持批量导入',
                    style: ZenText.label.copyWith(fontSize: 12),
                  ),
                ],
                if (_isAnimeMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    '追剧模式：输入剧的开始日期/星期/播出时间/期数，自动计算行列与周期',
                    style: ZenText.label.copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_isAnimeMode) ...[
            // ── 追剧/番模式：垂直排期编辑（纯剧语言配置，自动重算 DSL）──
            ZenSection(
              title: '追剧 / 番模式',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ZenActionButton(
                    icon: Icons.schedule,
                    label: '打开排期编辑（垂直时间轴）',
                    onPressed: _openAnimeEditor,
                  ),
                  const SizedBox(height: 8),
                  _ZenActionButton(
                    icon: Icons.movie_outlined,
                    label: '从开放 API 导入番剧',
                    onPressed: _openAnimeImport,
                    secondary: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '输入剧名/开播日期(或当前第几期)/星期/播出时间/总集数即可，'
                    '行列周期自动计算',
                    style: ZenText.label.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // ── 起始日期 ──
            ZenSection(
              title: '起始日期',
              child: _buildDateField(),
            ),
            const SizedBox(height: 12),
            // ── 周期配置 ──
            ZenSection(
              title: '周期配置',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ZenConfigSlider(
                    label: '周期数',
                    value: _cycleCount.toDouble(),
                    min: TimetableConfig.minCycles.toDouble(),
                    max: TimetableConfig.maxCycles.toDouble(),
                    divisions:
                        TimetableConfig.maxCycles - TimetableConfig.minCycles,
                    onChanged: (v) => setState(() => _cycleCount = v.round()),
                  ),
                  if (_isSchoolMode)
                    _ZenFixedLabel(
                      label: '每周期天数',
                      value: '7天（固定）',
                    )
                  else
                    _ZenConfigSlider(
                      label: '每周期天数 (1-7)',
                      value: _daysPerCycle.toDouble(),
                      min: TimetableConfig.minDaysPerCycle.toDouble(),
                      max: TimetableConfig.maxDaysPerCycle.toDouble(),
                      divisions: TimetableConfig.maxDaysPerCycle -
                          TimetableConfig.minDaysPerCycle,
                      onChanged: (v) => setState(() => _daysPerCycle = v.round()),
                    ),
                  _ZenConfigSlider(
                    label: '每天节数 (1-6)',
                    value: _slotsPerDay.toDouble(),
                    min: TimetableConfig.minSlotsPerDay.toDouble(),
                    max: TimetableConfig.maxSlotsPerDay.toDouble(),
                    divisions: TimetableConfig.maxSlotsPerDay -
                        TimetableConfig.minSlotsPerDay,
                    onChanged: (v) => setState(() => _slotsPerDay = v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 高级功能：左侧指示 / DSL 导入导出 / 清空 ──
          ZenSection(
            title: '高级功能',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '左侧指示显示控制',
                    style: ZenText.body.copyWith(fontWeight: FontWeight.w500),
                  ),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    _buildAdvancedControls(),
                  ],
                ),
                const SizedBox(height: 4),
                _ZenActionButton(
                  icon: Icons.upload_file,
                  label: '导入 DSL（含配置）',
                  onPressed: _openImport,
                  secondary: true,
                ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.download,
                  label: '导出 DSL（含配置）',
                  onPressed: _exportDsl,
                  secondary: true,
                ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.delete_outline,
                  label: '清空所有课程',
                  onPressed: _clearAll,
                  danger: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 第一层数据来源（模式预设）：学校模式保留 SICAU 导入 ──
          if (_isSchoolMode) ...[
            ZenSection(
              title: '数据来源',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ZenActionButton(
                    icon: Icons.school,
                    label: 'SICAU 课表导入',
                    onPressed: _openSicauImport,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '更多导入 / 导出入口在下方「高级功能」',
                    style: ZenText.label.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isAnimeMode) ...[
            // 追剧模式：Bangumi 新番作为另一个数据源预设
            ZenSection(
              title: '数据来源',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ZenActionButton(
                    icon: Icons.movie_outlined,
                    label: '从 Bangumi 拉取新番列表',
                    onPressed: _openAnimeImport,
                    secondary: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ──── 子组件：模式选择 ────
  Widget _buildModeSelector() {
    return Row(
      children: [
        Expanded(
          child: _ZenSegmentButton(
            label: '学校模式',
            selected: _isSchoolMode && !_isAnimeMode,
            onTap: () => setState(() {
              _isSchoolMode = true;
              _isAnimeMode = false;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ZenSegmentButton(
            label: '通用模式',
            selected: !_isSchoolMode && !_isAnimeMode,
            onTap: () => setState(() {
              _isSchoolMode = false;
              _isAnimeMode = false;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ZenSegmentButton(
            label: '追剧模式',
            selected: _isAnimeMode,
            onTap: () => setState(() {
              _isAnimeMode = true;
              _isSchoolMode = false;
            }),
          ),
        ),
      ],
    );
  }

  /// 高级功能：左侧指示显示控制（模式/宽度/时长/时间/自定义文字）
  Widget _buildAdvancedControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('左侧指示', style: ZenText.label),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ZenSegmentButton(
                label: '序号',
                selected: _leftLabelMode == 0,
                onTap: () => setState(() => _leftLabelMode = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ZenSegmentButton(
                label: '时间段',
                selected: _leftLabelMode == 1,
                onTap: () => setState(() => _leftLabelMode = 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ZenSegmentButton(
                label: '自定义',
                selected: _leftLabelMode == 2,
                onTap: () => setState(() => _leftLabelMode = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ZenConfigSlider(
          label: '左侧宽度 (px)',
          value: _leftWidth,
          min: 44,
          max: 110,
          divisions: 33,
          onChanged: (v) => setState(() => _leftWidth = v.roundToDouble()),
        ),
        if (_leftLabelMode == 1) ...[
          const SizedBox(height: 4),
          _ZenConfigSlider(
            label: '每节时长 (分钟)',
            value: _slotDurationMin.toDouble(),
            min: 15,
            max: 120,
            divisions: 21,
            onChanged: (v) => setState(() => _slotDurationMin = v.round()),
          ),
          const SizedBox(height: 8),
          Text('每节开始时间（HH:mm，自动计算结束）', style: ZenText.label),
          const SizedBox(height: 8),
          _buildTimeFields(),
        ],
        if (_leftLabelMode == 2) ...[
          const SizedBox(height: 8),
          Text('每节自定义文字（留空回退序号）', style: ZenText.label),
          const SizedBox(height: 8),
          _buildLabelFields(),
        ],
      ],
    );
  }

  // ──── 子组件：日期字段 ────
  // 通用模式：单个简单日期选择；学校模式：周数推算/自动对齐周一（fr #2）
  Widget _buildDateField() {
    if (!_isSchoolMode) {
      return _buildGeneralDateField();
    }
    return _buildSchoolDateField();
  }

  /// 通用模式：只一个日期入口，点按弹系统日期选择器，选哪天存哪天。
  Widget _buildGeneralDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final current = DateTime.tryParse(_startDateController.text);
            final picked = await showDatePicker(
              context: context,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              helpText: '选择开始日期',
            );
            if (picked == null) return;
            final iso = picked.toIso8601String().split('T')[0];
            setState(() => _startDateController.text = iso);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: zenCard(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: ZenColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('起始日期', style: ZenText.label),
                      const SizedBox(height: 2),
                      Text(
                        _startDateController.text,
                        style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZenColors.secondary, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 学校模式：原「周数推算 / 选日期自动对齐周一」双入口逻辑。
  Widget _buildSchoolDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final date = await showDialog<String>(
              context: context,
              builder: (_) => const WeekCalculatorDialog(),
            );
            if (date != null) {
              setState(() => _startDateController.text = date);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: zenCard(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: ZenColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('起始日期（周一）', style: ZenText.label),
                      const SizedBox(height: 2),
                      Text(
                        _startDateController.text,
                        style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZenColors.secondary, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 时间段模式：每节开始时间输入（HH:mm）
  Widget _buildTimeFields() {
    _ensureSlotLists();
    return Column(
      children: [
        for (int i = 0; i < _slotsPerDay; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '第${i + 1}节',
                    style: ZenText.body.copyWith(
                      color: ZenColors.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _slotStartTimes[i]),
                    keyboardType: TextInputType.datetime,
                    onChanged: (v) {
                      _slotStartTimes[i] = v.trim();
                    },
                    decoration: InputDecoration(
                      hintText: '08:00',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 自定义模式：每节自定义文字输入（留空回退序号）
  Widget _buildLabelFields() {
    _ensureSlotLists();
    return Column(
      children: [
        for (int i = 0; i < _slotsPerDay; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '第${i + 1}节',
                    style: ZenText.body.copyWith(
                      color: ZenColors.secondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _slotLabels[i]),
                    onChanged: (v) {
                      _slotLabels[i] = v.trim();
                    },
                    decoration: InputDecoration(
                      hintText: '如: 上午 / 09:00 更新',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: ZenColors.hair),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ──────────────────── Zen 风格子组件 ────────────────────

class _ZenSegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ZenSegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? ZenColors.sage.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(
            color: selected ? ZenColors.sage : ZenColors.hair,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? ZenColors.sage : ZenColors.secondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _ZenConfigSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _ZenConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: ZenText.body.copyWith(fontWeight: FontWeight.w500)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: ZenColors.sage.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value.round().toString(),
                style: ZenText.body.copyWith(
                  color: ZenColors.sage,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: ZenColors.sage,
            inactiveTrackColor: ZenColors.hair,
            thumbColor: ZenColors.sage,
            overlayColor: ZenColors.sage.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ZenFixedLabel extends StatelessWidget {
  final String label;
  final String value;

  const _ZenFixedLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ZenText.body.copyWith(fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: ZenColors.sage.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: ZenText.body.copyWith(
                color: ZenColors.sage,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZenActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;
  final bool secondary;

  const _ZenActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? ZenColors.mutedRed
        : (secondary ? ZenColors.secondary : ZenColors.sage);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: zenButton(
          foreground: color,
          border: color.withValues(alpha: 0.5),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: ZenText.button.copyWith(color: color)),
      ),
    );
  }
}
