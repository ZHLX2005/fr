// kvcli todo 行为模拟 — 调真实 GoFrame 后端的 /api/v1/kv 端点，
// 与 `lab/kvcli` CLI 端共享同一份存储。
//
// 真实链路：
//   - set   : POST   /api/v1/kv  body={key,value,ttl}
//   - get   : GET    /api/v1/kv/{key}   解析 KvItem.value
//   - delete: DELETE /api/v1/kv/{key}
//
// KV 只提供快照存储：task 完整 CRUD、tag(topic) 仅添加+删除、prompt 不做。
// 三把 key：todo:open / todo:done（Task[] JSON）、todo:topics（String[] JSON）。
// 无单条更新 API，所有写操作 = 读整把 key → 改数组 → 整把覆盖写回。
//
// 视觉骨架走 styles-skill → border-emphasis-style：
//   - 装饰元素统一主题色；操作按钮撞色编码语义
//   - 添加 = green / 主操作；完成 = blue / 读取+写入；删除/清空 = red / 危险

import 'dart:convert';
import '../../widgets/context_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/goframe/kv/kv_endpoint.dart';
import '../../api/goframe/group/group_endpoint.dart';
import '../../api/providers/api_providers.dart';
import '../../core/design/emphasis_button.dart';
import '../lab_container.dart';
import 'kvcli_todo/active_group_provider.dart';
import 'kvcli_todo/const_kvcli_todo.dart';
import 'kvcli_todo/kvcli_todo_dialogs.dart';
import 'kvcli_todo/kvcli_todo_models.dart';
import 'kvcli_todo/kvcli_todo_widgets.dart';

// ── 错误处理辅助 ──────────────────────────────────────────────────────────

/// 把任意异常压平成"错误消息"。ApiException(code/message) 已带语义，
/// 其他异常（TypeError/FormatException）走 message 兜底。
String _errMsg(Object e) {
  final s = e.toString();
  return s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

// ── Demo 入口 ─────────────────────────────────────────────────────────────

class KvcliTodoDemo extends DemoPage {
  @override
  String get title => 'KV 清单';

  @override
  String get slug => 'kvcli-todo';

  @override
  String get description => '调后端 /api/v1/kv 模拟 kvcli todo';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    // ConsumerWidget：让 Riverpod 注入 KvEndpoint + GroupEndpoint + 触发 rebuild
    return Consumer(
      builder: (context, ref, _) {
        final KvEndpoint kv;
        final GroupEndpoint groups;
        try {
          kv = ref.watch(kvEndpointProvider);
          groups = ref.watch(groupEndpointProvider);
        } catch (e) {
          return Scaffold(
            body: Center(child: Text('KV 端点初始化失败：${_errMsg(e)}')),
          );
        }
        return _KvcliTodoDemoPage(kv: kv, groups: groups);
      },
    );
  }
}

// ── 主页面 ────────────────────────────────────────────────────────────────

class _KvcliTodoDemoPage extends ConsumerStatefulWidget {
  const _KvcliTodoDemoPage({required this.kv, required this.groups});

  final KvEndpoint kv;
  final GroupEndpoint groups;

  @override
  ConsumerState<_KvcliTodoDemoPage> createState() => _KvcliTodoDemoPageState();
}

class _KvcliTodoDemoPageState extends ConsumerState<_KvcliTodoDemoPage> {
  final _topicCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();

  List<KvTask> _open = const [];
  List<KvTask> _done = const [];
  List<String> _topics = const [];
  List<KvGroup> _groups = const [];
  bool _loading = true;
  int _tab = 0; // 0 = 待办，1 = 已完成

  /// 写操作前的 refetch 期间为 true。避免并发点击叠加二次 refetch。
  bool _refreshing = false;

  /// composer 折叠态。默认展开（首次进入即可看到输入）。
  bool _composerExpanded = true;

  /// 筛选 topic 集合：空集合 = 全部显示；非空 = 任一命中即显示（OR）。
  Set<String> _filterTopics = const <String>{};

  /// 激活组注入 KV 的三元值：0 → null（后端回落默认组），>0 → 原值。
  int? get _gid {
    final gid = ref.read(activeGroupProvider);
    return gid == 0 ? null : gid;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // ── 网络层 ───────────────────────────────────────────────────────────

  Future<List<KvTask>> _readTasks(String key) async {
    final res = await widget.kv.get(key, groupId: _gid);
    // key 不存在 / 后端返回失败：当作空数组
    if (!res.isSuccess || res.data == null) return const <KvTask>[];
    return KvTask.parseList(res.data!.value);
  }

  Future<List<String>> _readTopics() async {
    final res = await widget.kv.get(KvCliTodoConst.keyTopics, groupId: _gid);
    if (!res.isSuccess || res.data == null) return const <String>[];
    final raw = res.data!.value.trim();
    if (raw.isEmpty) return const <String>[];
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      // 解析失败不阻塞 UI，留 debugPrint 排查
      debugPrint('kvcli_todo: parse topics failed, fallback to []');
      return const <String>[];
    }
  }

  Future<void> _writeKey(String key, String value) async {
    final res = await widget.kv.set(
      key: key,
      value: value,
      ttl: 0,
      groupId: _gid,
    );
    if (!res.isSuccess) {
      throw Exception('写 $key 失败: code=${res.code} ${res.message}');
    }
  }

  Future<void> _saveTasks(String key, List<KvTask> tasks) =>
      _writeKey(key, jsonEncode(tasks.map((t) => t.toJson()).toList()));

  Future<void> _saveTopics(List<String> topics) =>
      _writeKey(KvCliTodoConst.keyTopics, jsonEncode(topics));

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await ref.read(activeGroupProvider.notifier).load(); // 确保激活组已载入
    try {
      final groupRes = await widget.groups.list();
      final open = await _readTasks(KvCliTodoConst.keyOpen);
      final done = await _readTasks(KvCliTodoConst.keyDone);
      final topics = await _readTopics();
      if (!mounted) return;
      setState(() {
        _groups = (groupRes.isSuccess && groupRes.data != null)
            ? groupRes.data!
            : const [];
        _open = open;
        _done = done;
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('读取失败：${_errMsg(e)}');
    }
  }

  /// 写操作前的 refetch：把本地 _open / _done / _topics 替换为 server 最新值。
  /// 本地优先丢弃策略：本次操作将在 server 最新基础上叠加后再写回。
  /// 接受毫秒级竞态放弃（用户明确）。
  Future<void> _refreshLatest() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final open = await _readTasks(KvCliTodoConst.keyOpen);
      final done = await _readTasks(KvCliTodoConst.keyDone);
      final topics = await _readTopics();
      if (!mounted) return;
      setState(() {
        _open = open;
        _done = done;
        _topics = topics;
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ── 操作层 ───────────────────────────────────────────────────────────

  Future<void> _add() async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    final topic = _topicCtrl.text.trim();
    final text = _textCtrl.text.trim();
    if (topic.isEmpty || text.isEmpty) {
      _toast('主题与任务文本均必填');
      return;
    }

    var maxId = 0;
    for (final t in _open) {
      if (t.id > maxId) maxId = t.id;
    }
    final task = KvTask(
      id: maxId + 1,
      topic: topic,
      text: text,
      createdAt: DateTime.now().toIso8601String(),
    );
    final next = [..._open, task];
    // 主题不在快捷列表 → 一并写入 todo:topics（两把 key 一起写，失败整单放弃）
    final addTopic = !_topics.contains(topic);
    final nextTopics = addTopic ? [..._topics, topic] : _topics;
    try {
      await _saveTasks(KvCliTodoConst.keyOpen, next);
      if (addTopic) await _saveTopics(nextTopics);
    } catch (e) {
      _toast('提交失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() {
      _open = next;
      if (addTopic) _topics = nextTopics;
    });
    _textCtrl.clear();
    _textFocus.requestFocus();
  }

  Future<void> _markDone(KvTask task) async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    if (!mounted) return;
    final note = await showKvDoneResultDialog(context, task);
    if (note == null) return; // 用户取消

    final completed = task.copyWith(
      doneAt: DateTime.now().toIso8601String(),
      note: note,
    );
    final open = _open.where((t) => t.id != task.id).toList();
    final done = [..._done, completed];
    try {
      await _saveTasks(KvCliTodoConst.keyOpen, open);
      await _saveTasks(KvCliTodoConst.keyDone, done);
    } catch (e) {
      _toast('标记完成失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() {
      _open = open;
      _done = done;
    });
  }

  Future<void> _editTask(KvTask task, {required bool isDone}) async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    if (!mounted) return;
    final r = await showKvTaskEditDialog(context, task: task, isDone: isDone);
    if (r == null) return;
    final updated = task.edited(topic: r.topic, text: r.text, note: r.note);
    try {
      if (isDone) {
        final done = _done.map((t) => t.id == task.id ? updated : t).toList();
        await _saveTasks(KvCliTodoConst.keyDone, done);
        if (!mounted) return;
        setState(() => _done = done);
      } else {
        final open = _open.map((t) => t.id == task.id ? updated : t).toList();
        await _saveTasks(KvCliTodoConst.keyOpen, open);
        if (!mounted) return;
        setState(() => _open = open);
      }
    } catch (e) {
      _toast('保存失败：${_errMsg(e)}');
    }
  }

  Future<void> _deleteTask(KvTask task, {required bool isDone}) async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    if (!mounted) return;
    final ok = await showKvTaskDeleteConfirm(context, task);
    if (!ok) return;
    try {
      if (isDone) {
        final done = _done.where((t) => t.id != task.id).toList();
        await _saveTasks(KvCliTodoConst.keyDone, done);
        if (!mounted) return;
        setState(() => _done = done);
      } else {
        final open = _open.where((t) => t.id != task.id).toList();
        await _saveTasks(KvCliTodoConst.keyOpen, open);
        if (!mounted) return;
        setState(() => _open = open);
      }
    } catch (e) {
      _toast('删除失败：${_errMsg(e)}');
    }
  }

  /// 克隆已完成任务回待办：新 id、保留 topic/text，重新走待办流程。
  Future<void> _cloneTask(KvTask task) async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    var maxId = 0;
    for (final t in _open) {
      if (t.id > maxId) maxId = t.id;
    }
    final cloned = KvTask(
      id: maxId + 1,
      topic: task.topic,
      text: task.text,
      createdAt: DateTime.now().toIso8601String(),
    );
    final next = [..._open, cloned];
    try {
      await _saveTasks(KvCliTodoConst.keyOpen, next);
    } catch (e) {
      _toast('克隆失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _open = next);
    _toast('已克隆回待办：#${cloned.id}');
  }

  /// 把全部已完成归档到冷数据 key（按日期分片，app 只写不查），再清空已完成。
  Future<void> _clearDoneToCold() async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    if (!mounted) return;
    final ok = await showKvClearDoneConfirm(context, _done.length);
    if (!ok) return;
    final coldKey = KvCliTodoConst.coldKeyFor(DateTime.now());
    try {
      // 同一天多次清理 → 合并到同一冷数据 key
      final existing = await _readTasks(coldKey);
      final merged = [...existing, ..._done];
      await _writeKey(
        coldKey,
        jsonEncode(merged.map((t) => t.toJson()).toList()),
      );
      await widget.kv.delete(KvCliTodoConst.keyDone, groupId: _gid);
    } catch (e) {
      _toast('清理失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _done = const []);
  }

  Future<bool> _addTopic() async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return false;
    }
    await _refreshLatest();
    if (!mounted) return false;
    final name = await showKvAddTopicDialog(
      context,
      initial: _topicCtrl.text.trim(),
    );
    if (name == null || name.isEmpty) return false;
    if (_topics.contains(name)) {
      _toast('快捷 topic「$name」已存在');
      return false;
    }
    final next = [..._topics, name];
    try {
      await _saveTopics(next);
    } catch (e) {
      _toast('添加失败：${_errMsg(e)}');
      return false;
    }
    if (!mounted) return false;
    setState(() => _topics = next);
    return true;
  }

  Future<bool> _deleteTopic(String topic) async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return false;
    }
    await _refreshLatest();
    final next = _topics.where((t) => t != topic).toList();
    try {
      await _saveTopics(next);
    } catch (e) {
      _toast('删除失败：${_errMsg(e)}');
      return false;
    }
    if (!mounted) return false;
    setState(() => _topics = next);
    return true;
  }

  Future<void> _clearAll() async {
    if (_refreshing || _loading) {
      _toast('正在同步最新数据，请稍候');
      return;
    }
    await _refreshLatest();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空两把 key？'),
        content: const Text('将删除 todo:open 与 todo:done 两个 key，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: EmphasisButton.dangerEmphasis(context),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.kv.delete(KvCliTodoConst.keyOpen, groupId: _gid);
      await widget.kv.delete(KvCliTodoConst.keyDone, groupId: _gid);
    } catch (e) {
      _toast('清空失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() {
      _open = const [];
      _done = const [];
    });
  }

  void _applyTopicChip(String topic) {
    // 折叠态下点 chip：先展开 composer 再填主题，否则用户看不到填了什么。
    if (!_composerExpanded) {
      setState(() => _composerExpanded = true);
    }
    _topicCtrl.text = topic;
    _topicCtrl.selection = TextSelection.collapsed(offset: topic.length);
    // 等下一帧布局完成（折叠动画后）再聚焦，避免焦点落到 0 高度的输入框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  void _toggleComposer() {
    setState(() => _composerExpanded = !_composerExpanded);
  }

  /// 切换某 topic 的筛选态；空集合 = 全部，等价于"全部"chip。
  void _toggleFilter(String topic) {
    setState(() {
      final next = Set<String>.from(_filterTopics);
      if (next.contains(topic)) {
        next.remove(topic);
      } else {
        next.add(topic);
      }
      _filterTopics = next;
    });
  }

  void _clearFilter() {
    if (_filterTopics.isEmpty) return;
    setState(() => _filterTopics = const <String>{});
  }

  /// 应用筛选：空集合直接放行；否则保留 topic 命中的（OR）。
  List<KvTask> _applyFilter(List<KvTask> source) {
    if (_filterTopics.isEmpty) return source;
    return source.where((t) => _filterTopics.contains(t.topic)).toList();
  }

  // 独立快捷 topic 区块：标题 + ⚙ 管理；chip 横向滚动、点击回填
  Widget _buildQuickTopicsSection(ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '快捷 topic',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              IconButton(
                tooltip: '管理',
                icon: Icon(Icons.settings_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _openTopicManager,
              ),
            ],
          ),
          SizedBox(height: 4),
          if (_topics.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '暂无快捷 topic，提交任务时自动收集',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in _topics)
                    Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: KvTopicChip(
                        label: t,
                        onTap: () => _applyTopicChip(t),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openTopicManager() async {
    await showKvTopicManagerSheet(
      context,
      topics: _topics,
      onAdd: _addTopic,
      onDelete: _deleteTopic,
    );
  }

  /// 激活组显示名：0→默认；命中 _groups 用其 name；找不到→#id。
  String _groupLabel(int gid) {
    if (gid == 0) return '默认';
    for (final g in _groups) {
      if (g.id == gid) return g.name;
    }
    return '#$gid';
  }

  Future<void> _openWorkspaceSheet() async {
    final gid = ref.read(activeGroupProvider);
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('工作空间',
                    style: Theme.of(sheetCtx).textTheme.titleMedium),
                SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _workspaceTile(
                        sheetCtx,
                        scheme,
                        id: 0,
                        name: '默认组（服务端）',
                        role: '',
                        active: gid == 0,
                      ),
                      for (final grp in _groups)
                        _workspaceTile(
                          sheetCtx,
                          scheme,
                          id: grp.id,
                          name: grp.name,
                          role: grp.myRole,
                          active: gid == grp.id,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || selected == gid) return;
    await _setActiveGroup(selected);
  }

  Widget _workspaceTile(
    BuildContext ctx,
    ColorScheme scheme, {
    required int id,
    required String name,
    required String role,
    required bool active,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: active ? scheme.primary : scheme.outline,
      ),
      title: Text(name),
      subtitle: role.isNotEmpty
          ? Text(role, style: TextStyle(fontSize: 11, color: scheme.outline))
          : null,
      trailing: active
          ? Text('当前',
              style: TextStyle(fontSize: 11, color: scheme.primary))
          : null,
      onTap: () => Navigator.pop(ctx, id),
    );
  }

  Future<void> _setActiveGroup(int id) async {
    await ref.read(activeGroupProvider.notifier).set(id);
    if (!mounted) return;
    await _loadAll();
  }

  /// AppBar actions 第 1 位：工作空间切换按钮。
  /// 形态：IconButton + tooltip + 限宽组名，避免 chip + 文字塞进窄屏 title 行导致挤压交错。
  Widget _buildWorkspaceAction(ColorScheme scheme, int gid) {
    final name = _groupLabel(gid);
    return IconButton(
      tooltip: '工作空间：$name（点击切换）',
      onPressed: _loading ? null : _openWorkspaceSheet,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspaces_outlined, size: 18, color: scheme.primary),
          SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 72),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors.scheme;
    final gid = ref.watch(activeGroupProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KV 清单'),
        actions: [
          _buildWorkspaceAction(scheme, gid),
          IconButton(
            tooltip: '刷新',
            icon: Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAll,
          ),
          IconButton(
            tooltip: '清空两把 key',
            icon: Icon(Icons.delete_outline),
            onPressed: _open.isEmpty && _done.isEmpty ? null : _clearAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                KvTabChip(
                  label: '待办 (${_open.length})',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                SizedBox(width: 8),
                KvTabChip(
                  label: '已完成 (${_done.length})',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildComposerSection(scheme),
                Divider(height: 1),
                _buildQuickTopicsSection(scheme),
                Divider(height: 1),
                _buildFilterSection(scheme),
                Divider(height: 1),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  /// composer 区块：顶部一行 toggle 按钮，展开时显示原输入框，折叠时仅一行。
  Widget _buildComposerSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggleComposer,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 16,
                  color: scheme.outline,
                ),
                SizedBox(width: 4),
                Text(
                  _composerExpanded ? '添加任务' : '添加任务（点击展开）',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                Icon(
                  _composerExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: scheme.outline,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: _composerExpanded
              ? _buildComposer(scheme)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildComposer(ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _topicCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '主题 (--topic)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: 8),
              OutlinedButton(
                onPressed: _loading ? null : _add,
                style: EmphasisButton.borderEmphasis(
                  context,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('+'),
              ),
            ],
          ),
          SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            focusNode: _textFocus,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: '任务文本',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 筛选行：左「全部」chip（清空），右各 topic chip（多选 OR）。
  /// 无 topic 时整行隐藏，避免空视觉噪音。
  Widget _buildFilterSection(ColorScheme scheme) {
    if (_topics.isEmpty) return const SizedBox.shrink();
    final hasFilter = _filterTopics.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '按 topic 筛选',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasFilter) ...[
                SizedBox(width: 6),
                Text(
                  '· 已选 ${_filterTopics.length}',
                  style: TextStyle(fontSize: 11, color: scheme.primary),
                ),
              ],
            ],
          ),
          SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                KvTopicChip(
                  label: '全部',
                  selected: !hasFilter,
                  onTap: _clearFilter,
                ),
                SizedBox(width: 6),
                for (final t in _topics) ...[
                  KvTopicChip(
                    label: t,
                    selected: _filterTopics.contains(t),
                    onTap: () => _toggleFilter(t),
                  ),
                  SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final raw = _tab == 0 ? _open : _done;
    final isOpen = _tab == 0;
    final list = _applyFilter(raw);
    if (list.isEmpty) {
      final isFiltering = _filterTopics.isNotEmpty;
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            isFiltering
                ? '当前筛选下无任务'
                : (isOpen ? '暂无待办任务' : '暂无已完成任务'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Column(
      children: [
        if (!isOpen) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Text(
                  '已完成 ${_done.length} 条',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Spacer(),
                TextButton.icon(
                  onPressed: _clearDoneToCold,
                  style: EmphasisButton.dangerEmphasis(context),
                  icon: Icon(Icons.archive_outlined, size: 16),
                  label: const Text('清理到冷数据'),
                ),
              ],
            ),
          ),
          SizedBox(height: 4),
        ],
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final task = list[i];
              return KvTaskCard(
                task: task,
                isOpen: isOpen,
                onDone: isOpen ? () => _markDone(task) : null,
                onEdit: () => _editTask(task, isDone: !isOpen),
                onDelete: () => _deleteTask(task, isDone: !isOpen),
                onClone: isOpen ? null : () => _cloneTask(task),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── 注册 ──────────────────────────────────────────────────────────────────

void registerKvcliTodoDemo() {
  demoRegistry.register(KvcliTodoDemo());
}
