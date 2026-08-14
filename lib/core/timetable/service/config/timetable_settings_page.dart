import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/timetable_store.dart';
import 'anime_dsl_generator.dart';
import 'anime_source_adapter.dart';
import 'sicau_import_dialog.dart';
import 'timetable_advanced_settings_page.dart';
import 'timetable_anime_editor_page.dart';
import 'timetable_anime_import_dialog.dart';
import '../../../../widgets/theme/zen_theme.dart';

/// 课表设置页 —— 第一层：模式选择 + 数据来源预设。
///
/// 非常用数字配置（周期数/天数/节数/起始日期/左侧指示/DSL 管理）已拆到
/// [TimetableAdvancedSettingsPage] 独立页面，入口在本页底部。
class TimetableSettingsPage extends ConsumerStatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  ConsumerState<TimetableSettingsPage> createState() =>
      _TimetableSettingsPageState();
}

class _TimetableSettingsPageState
    extends ConsumerState<TimetableSettingsPage> {
  late bool _isSchoolMode;
  late bool _isAnimeMode;

  @override
  void initState() {
    super.initState();
    final config = ref.read(TimetableStore.provider).config;
    _isSchoolMode = config.isSchoolMode;
    _isAnimeMode = config.isAnimeMode;
  }

  Future<void> _save() async {
    final store = ref.read(TimetableStore.provider.notifier);
    await store.updateConfig(
      isSchoolMode: _isSchoolMode,
      isAnimeMode: _isAnimeMode,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('模式已保存')));
    Navigator.pop(context);
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

  /// 打开垂直排期编辑页（剧模型 CRUD，自动派生 DSL）
  Future<void> _openAnimeEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TimetableAnimeEditorPage()),
    );
  }

  /// 从开放 API 导入番剧 → 追加进剧模型（不覆盖）
  Future<void> _openAnimeImport() async {
    final drafts = await showDialog<List<AnimeDraft>>(
      context: context,
      builder: (_) => const TimetableAnimeImportDialog(),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    final store = ref.read(TimetableStore.provider.notifier);
    await store.importAnimeSeries(
      drafts
          .map(
            (d) => AnimeSeriesDraft(
              title: d.title,
              startDateIso: d.startDateIso ?? '',
              weekday: d.weekday ?? 1,
              time: d.time ?? '',
              episodes: d.episodes ?? 13,
            ),
          )
          .toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已导入 ${drafts.length} 部剧（请在排期编辑中补全播出时间）',
        ),
      ),
    );
  }

  Future<void> _openAdvanced() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TimetableAdvancedSettingsPage(),
      ),
    );
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
          // ── 模式选择（第一层）──
          ZenSection(
            title: '课表模式',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildModeSelector(),
                const SizedBox(height: 8),
                Text(
                  _isAnimeMode
                      ? '追剧模式：剧模型驱动，行列周期自动计算'
                      : (_isSchoolMode
                            ? '学校模式：周一为起始日期，7天固定'
                            : '通用模式：自由配置，默认一周7天·每天5节·20周期'),
                  style: ZenText.label.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 数据来源（第一层预设）──
          _buildDataSourceSection(),
          const SizedBox(height: 12),
          // ── 高级设置入口（独立页面承载非常用配置）──
          ZenSection(
            title: '高级设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ZenActionButton(
                  icon: Icons.tune,
                  label: '打开高级设置（周期/日期/左侧指示/DSL）',
                  onPressed: _openAdvanced,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSourceSection() {
    if (_isAnimeMode) {
      // 追剧模式：排期编辑（主）+ API 导入（辅助）
      return ZenSection(
        title: '数据来源',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ZenActionButton(
              icon: Icons.schedule,
              label: '打开排期编辑（剧模型 CRUD）',
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
              '剧变更后自动重算课表，无需手动生成 DSL',
              style: ZenText.label.copyWith(fontSize: 11),
            ),
          ],
        ),
      );
    }
    if (_isSchoolMode) {
      // 学校模式：只保留 SICAU 导入
      return ZenSection(
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
              '其他导入 / 导出入口在「高级设置」',
              style: ZenText.label.copyWith(fontSize: 11),
            ),
          ],
        ),
      );
    }
    // 通用模式：无预设，提示走高级设置 DSL 导入
    return ZenSection(
      title: '数据来源',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ZenActionButton(
            icon: Icons.edit_note,
            label: '通用模式：在高级设置导入 DSL',
            onPressed: _openAdvanced,
            secondary: true,
          ),
        ],
      ),
    );
  }

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

class _ZenActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool secondary;

  const _ZenActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = secondary ? ZenColors.secondary : ZenColors.sage;
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
