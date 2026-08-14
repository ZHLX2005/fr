// 管理界面 —— 实体 / 关系词 / 规则 三个 Tab 的完整 CRUD。
//
// 每次变更：调用 store 语义方法 → save → 通过 [onDataChanged] 把新快照
// 交回页面壳（重建引擎 + 持久化已由 store 完成）。
// 删除实体/关系词时 store 会联动清理引用它的规则，避免悬空边。

import 'package:flutter/material.dart';

import '../../../../widgets/theme/zen_theme.dart';
import 'const_relation_calc.dart';
import 'relation_calc_models.dart';
import 'relation_calc_store.dart';

class ManageView extends StatefulWidget {
  const ManageView({
    super.key,
    required this.data,
    required this.onDataChanged,
  });

  final RelationGraphData data;
  final ValueChanged<RelationGraphData> onDataChanged;

  @override
  State<ManageView> createState() => _ManageViewState();
}

class _ManageViewState extends State<ManageView> {
  final RelationCalcStore _store = RelationCalcStore.instance;

  Future<void> _apply(Future<RelationGraphData> Function() op) async {
    final next = await op();
    widget.onDataChanged(next);
  }

  // ---------------------------------------------------------------------
  // 实体 Tab
  // ---------------------------------------------------------------------

  Future<void> _editEntity(RelationEntity? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZenColors.surface,
        title: Text(existing == null
            ? RelationCalcUiText.addEntity
            : RelationCalcUiText.editEntity),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: RelationCalcUiText.nameLabel,
                hintText: '如：爷爷',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: RelationCalcUiText.noteLabel,
                hintText: '如：父亲的父亲',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(RelationCalcUiText.cancel,
                style: const TextStyle(color: ZenColors.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(RelationCalcUiText.save,
                style: const TextStyle(color: ZenColors.sage)),
          ),
        ],
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    final entity = RelationEntity(
      id: existing?.id ?? RelationCalcStore.newId('e'),
      name: nameCtrl.text.trim(),
      note: noteCtrl.text.trim(),
    );
    await _apply(() => _store.upsertEntity(entity));
  }

  Future<void> _deleteEntity(RelationEntity e) async {
    final ok = await ZenConfirmDialog.show(
      context: context,
      title: RelationCalcUiText.delete,
      message: '删除「${e.name}」？引用它的规则也会一并删除。',
      onConfirm: () {},
      confirmLabel: RelationCalcUiText.delete,
    );
    if (!ok) return;
    await _apply(() => _store.deleteEntity(e.id));
  }

  // ---------------------------------------------------------------------
  // 关系词 Tab
  // ---------------------------------------------------------------------

  Future<void> _editTerm(RelationTerm? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZenColors.surface,
        title: Text(existing == null
            ? RelationCalcUiText.addTerm
            : RelationCalcUiText.editTerm),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: RelationCalcUiText.nameLabel,
            hintText: '如：上级',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(RelationCalcUiText.cancel,
                style: const TextStyle(color: ZenColors.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(RelationCalcUiText.save,
                style: const TextStyle(color: ZenColors.sage)),
          ),
        ],
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    final term = RelationTerm(
      id: existing?.id ?? RelationCalcStore.newId('t'),
      name: nameCtrl.text.trim(),
    );
    await _apply(() => _store.upsertTerm(term));
  }

  Future<void> _deleteTerm(RelationTerm t) async {
    final ok = await ZenConfirmDialog.show(
      context: context,
      title: RelationCalcUiText.delete,
      message: '删除关系词「${t.name}」？引用它的规则也会一并删除。',
      onConfirm: () {},
      confirmLabel: RelationCalcUiText.delete,
    );
    if (!ok) return;
    await _apply(() => _store.deleteTerm(t.id));
  }

  // ---------------------------------------------------------------------
  // 规则 Tab
  // ---------------------------------------------------------------------

  Future<void> _editRule(RelationRule? existing) async {
    final entities = widget.data.entities;
    final terms = widget.data.terms;
    if (entities.isEmpty || terms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加实体和关系词')),
      );
      return;
    }
    String fromId = existing?.fromId ?? entities.first.id;
    String termId = existing?.termId ?? terms.first.id;
    String toId = existing?.toId ??
        (entities.length > 1 ? entities[1].id : entities.first.id);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: ZenColors.surface,
          title: Text(RelationCalcUiText.addRule),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: fromId,
                decoration: const InputDecoration(
                    labelText: RelationCalcUiText.fromLabel),
                items: [
                  for (final e in entities)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setDlg(() => fromId = v ?? fromId),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: termId,
                decoration: const InputDecoration(
                    labelText: RelationCalcUiText.termLabel),
                items: [
                  for (final t in terms)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setDlg(() => termId = v ?? termId),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: toId,
                decoration: const InputDecoration(
                    labelText: RelationCalcUiText.toLabel),
                items: [
                  for (final e in entities)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setDlg(() => toId = v ?? toId),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(RelationCalcUiText.cancel,
                  style: const TextStyle(color: ZenColors.secondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(RelationCalcUiText.save,
                  style: const TextStyle(color: ZenColors.sage)),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final rule = RelationRule(
      id: existing?.id ?? RelationCalcStore.newId('r'),
      fromId: fromId,
      termId: termId,
      toId: toId,
    );
    await _apply(() => _store.upsertRule(rule));
  }

  Future<void> _deleteRule(RelationRule r) async {
    final ok = await ZenConfirmDialog.show(
      context: context,
      title: RelationCalcUiText.delete,
      message: '删除这条规则？',
      onConfirm: () {},
      confirmLabel: RelationCalcUiText.delete,
    );
    if (!ok) return;
    await _apply(() => _store.deleteRule(r.id));
  }

  // ---------------------------------------------------------------------
  // 列表渲染
  // ---------------------------------------------------------------------

  String _entityName(String id) {
    for (final e in widget.data.entities) {
      if (e.id == id) return e.name;
    }
    return '?';
  }

  String _termName(String id) {
    for (final t in widget.data.terms) {
      if (t.id == id) return t.name;
    }
    return '?';
  }

  Widget _listCard({
    required Widget leading,
    required Widget title,
    Widget? subtitle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: zenCard(),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: ZenText.button,
                  child: title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(style: ZenText.label, child: subtitle),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: ZenColors.secondary),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: ZenColors.mutedRed),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: ZenColors.sage,
            unselectedLabelColor: ZenColors.secondary,
            indicatorColor: ZenColors.sage,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: RelationCalcUiText.entitiesTab),
              Tab(text: RelationCalcUiText.termsTab),
              Tab(text: RelationCalcUiText.rulesTab),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildEntitiesTab(),
                _buildTermsTab(),
                _buildRulesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntitiesTab() {
    final entities = widget.data.entities;
    if (entities.isEmpty) {
      return ZenEmptyState(
        icon: Icons.person_outline,
        message: '还没有实体',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final e in entities)
          _listCard(
            leading: const Icon(Icons.person, color: ZenColors.sage, size: 20),
            title: Text(e.name),
            subtitle: e.note.isEmpty ? null : Text(e.note),
            onEdit: () => _editEntity(e),
            onDelete: () => _deleteEntity(e),
          ),
        const SizedBox(height: 4),
        Center(
          child: OutlinedButton(
            onPressed: () => _editEntity(null),
            style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
            child: const Text('+'),
          ),
        ),
      ],
    );
  }

  Widget _buildTermsTab() {
    final terms = widget.data.terms;
    if (terms.isEmpty) {
      return ZenEmptyState(
        icon: Icons.merge_type,
        message: '还没有关系词',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final t in terms)
          _listCard(
            leading: const Icon(Icons.merge_type, color: ZenColors.sage, size: 20),
            title: Text(t.name),
            onEdit: () => _editTerm(t),
            onDelete: () => _deleteTerm(t),
          ),
        const SizedBox(height: 4),
        Center(
          child: OutlinedButton(
            onPressed: () => _editTerm(null),
            style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
            child: const Text('+'),
          ),
        ),
      ],
    );
  }

  Widget _buildRulesTab() {
    final rules = widget.data.rules;
    if (rules.isEmpty) {
      return ZenEmptyState(
        icon: Icons.account_tree_outlined,
        message: '还没有规则',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final r in rules)
          _listCard(
            leading:
                const Icon(Icons.account_tree, color: ZenColors.sage, size: 20),
            title: Text(
                '${_entityName(r.fromId)} 的 ${_termName(r.termId)} = ${_entityName(r.toId)}'),
            onEdit: () => _editRule(r),
            onDelete: () => _deleteRule(r),
          ),
        const SizedBox(height: 4),
        Center(
          child: OutlinedButton(
            onPressed: () => _editRule(null),
            style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
            child: const Text('+'),
          ),
        ),
      ],
    );
  }
}
