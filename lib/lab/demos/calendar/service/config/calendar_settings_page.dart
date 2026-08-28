import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/calendar_config.dart';
import '../../data/lab_calendar_provider.dart';
import '../../data/lab_people_provider.dart';
import 'calendar_import_dialog.dart';
import '../../../../../core/theme/component/zen/zen_theme.dart';

/// 日历设置页（仿 timetable 主设置页第一层结构 + 高级入口）
///
/// 提供：
/// - group 列表/切换/新建/重命名/删除（仿 timetable 多空间）
/// - DSL 导出/导入入口（高级操作）
class CalendarSettingsPage extends StatefulWidget {
  const CalendarSettingsPage({super.key});

  @override
  State<CalendarSettingsPage> createState() => _CalendarSettingsPageState();
}

class _CalendarSettingsPageState extends State<CalendarSettingsPage> {
  @override
  Widget build(BuildContext context) {
    // 监听 provider 变化：group 列表 / 激活 group 变化时立即重建
    // 使用 provider.watch (provider 包) — ConsumerStatefulWidget 不支持 context.watch
    final cal = Provider.of<LabCalendarProvider>(context, listen: true);
    final people = LabPeopleProvider.current;
    if (people == null) {
      return const Scaffold(body: Center(child: Text('日历尚未初始化')));
    }
    final groups = cal.groups;
    final activeId = cal.activeGroupId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日历设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ZenSection(
            title: '日历 group（多空间）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in groups)
                  _GroupTile(
                    group: g,
                    active: g.id == activeId,
                    onSelect: () => _switchTo(g.id),
                    onRename: () => _renameGroup(g.id),
                    onDelete: g.id == CalendarGroup.defaultGroupId
                        ? null
                        : () => _deleteGroup(g.id),
                  ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.add,
                  label: '新建日历 group',
                  onPressed: _createGroup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ZenSection(
            title: 'DSL 管理（高级）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ZenActionButton(
                  icon: Icons.upload_file,
                  label: '导入日历 DSL',
                  onPressed: () => _openImport(),
                ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.download,
                  label: '导出当前 group 为 DSL',
                  onPressed: _exportDsl,
                  secondary: true,
                ),
                const SizedBox(height: 8),
                _ZenActionButton(
                  icon: Icons.delete_outline,
                  label: '清空当前 group 的所有事件',
                  onPressed: _clearGroup,
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchTo(String id) async {
    final cal = LabCalendarProvider.current!;
    final people = LabPeopleProvider.current!;
    await cal.setActiveGroup(id);
    await people.setActiveGroup(id);
    if (mounted) setState(() {}); // 兜底 rebuild（provider notify 失败时）
  }

  Future<void> _createGroup() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建日历 group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如: 工作 / 个人 / 追剧'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final cal = LabCalendarProvider.current!;
    final people = LabPeopleProvider.current!;
    await cal.createGroup(name);
    await people.setActiveGroup(cal.activeGroupId);
    if (mounted) setState(() {});
  }

  Future<void> _renameGroup(String id) async {
    final cal = LabCalendarProvider.current!;
    final g = cal.groups.firstWhere((x) => x.id == id);
    final ctrl = TextEditingController(text: g.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名 group'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await cal.renameGroup(id, name);
    if (mounted) setState(() {});
  }

  Future<void> _deleteGroup(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 group'),
        content: const Text('该 group 下的所有事件和人将一并删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final cal = LabCalendarProvider.current!;
    final people = LabPeopleProvider.current!;
    await people.removeByGroup(id);
    await cal.deleteGroup(id);
    if (mounted) setState(() {});
  }

  Future<void> _openImport() async {
    await showDialog(
      context: context,
      builder: (_) => const CalendarImportDialog(),
    );
  }

  Future<void> _exportDsl() async {
    final cal = LabCalendarProvider.current!;
    final dsl = cal.exportDsl();
    if (dsl.trim().isEmpty || !dsl.contains('event')) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前 group 无事件')));
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: dsl));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('DSL 已复制到剪贴板')));
    }
  }

  Future<void> _clearGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空 group 事件'),
        content: const Text('当前 group 的所有事件将删除（人保留），不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final cal = LabCalendarProvider.current!;
    await cal.clearActiveGroupItems();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清空')));
    }
  }
}

class _GroupTile extends StatelessWidget {
  final CalendarGroup group;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  const _GroupTile({
    required this.group,
    required this.active,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_off,
        color: active ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        group.name,
        style: ZenText.body.copyWith(color: scheme.onSurface),
      ),
      subtitle: active
          ? Text('当前', style: TextStyle(fontSize: 11, color: scheme.primary))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: '删除',
              onPressed: onDelete,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: '重命名',
            onPressed: onRename,
          ),
        ],
      ),
      onTap: onSelect,
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
    final scheme = Theme.of(context).colorScheme;
    final color = danger
        ? scheme.error
        : (secondary ? scheme.onSurfaceVariant : scheme.primary);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
