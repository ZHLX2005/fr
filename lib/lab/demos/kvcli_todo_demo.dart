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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/goframe/kv/kv_endpoint.dart';
import '../../api/providers/api_providers.dart';
import '../../core/design/emphasis_button.dart';
import '../lab_container.dart';
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
    // ConsumerWidget：让 Riverpod 注入 KvEndpoint + 触发 rebuild
    return Consumer(
      builder: (context, ref, _) {
        final KvEndpoint kv;
        try {
          kv = ref.watch(kvEndpointProvider);
        } catch (e) {
          return Scaffold(
            body: Center(child: Text('KV 端点初始化失败：${_errMsg(e)}')),
          );
        }
        return _KvcliTodoDemoPage(kv: kv);
      },
    );
  }
}

// ── 主页面 ────────────────────────────────────────────────────────────────

class _KvcliTodoDemoPage extends StatefulWidget {
  const _KvcliTodoDemoPage({required this.kv});

  final KvEndpoint kv;

  @override
  State<_KvcliTodoDemoPage> createState() => _KvcliTodoDemoPageState();
}

class _KvcliTodoDemoPageState extends State<_KvcliTodoDemoPage> {
  final _topicCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();

  List<KvTask> _open = const [];
  List<KvTask> _done = const [];
  List<String> _topics = const [];
  bool _loading = true;
  int _tab = 0; // 0 = 待办，1 = 已完成

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
    final res = await widget.kv.get(key);
    // key 不存在 / 后端返回失败：当作空数组
    if (!res.isSuccess || res.data == null) return const <KvTask>[];
    return KvTask.parseList(res.data!.value);
  }

  Future<List<String>> _readTopics() async {
    final res = await widget.kv.get(KvCliTodoConst.keyTopics);
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
    final res = await widget.kv.set(key: key, value: value, ttl: 0);
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
    try {
      final open = await _readTasks(KvCliTodoConst.keyOpen);
      final done = await _readTasks(KvCliTodoConst.keyDone);
      final topics = await _readTopics();
      if (!mounted) return;
      setState(() {
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

  // ── 操作层 ───────────────────────────────────────────────────────────

  Future<void> _add() async {
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
    try {
      await _saveTasks(KvCliTodoConst.keyOpen, next);
    } catch (e) {
      _toast('提交失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _open = next);
    _textCtrl.clear();
    _textFocus.requestFocus();
  }

  Future<void> _markDone(KvTask task) async {
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

  Future<void> _addTopic() async {
    final name = await showKvAddTopicDialog(
      context,
      initial: _topicCtrl.text.trim(),
    );
    if (name == null || name.isEmpty) return;
    if (_topics.contains(name)) {
      _toast('快捷 topic「$name」已存在');
      return;
    }
    final next = [..._topics, name];
    try {
      await _saveTopics(next);
    } catch (e) {
      _toast('添加失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _topics = next);
  }

  Future<void> _deleteTopic(String topic) async {
    final next = _topics.where((t) => t != topic).toList();
    try {
      await _saveTopics(next);
    } catch (e) {
      _toast('删除失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _topics = next);
  }

  Future<void> _clearAll() async {
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
      await widget.kv.delete(KvCliTodoConst.keyOpen);
      await widget.kv.delete(KvCliTodoConst.keyDone);
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
    _topicCtrl.text = topic;
    _topicCtrl.selection = TextSelection.collapsed(offset: topic.length);
    _textFocus.requestFocus();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KV 清单'),
        backgroundColor: scheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadAll,
          ),
          IconButton(
            tooltip: '清空两把 key',
            icon: const Icon(Icons.delete_outline),
            onPressed: _open.isEmpty && _done.isEmpty ? null : _clearAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                KvTabChip(
                  label: '待办 (${_open.length})',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildComposer(scheme),
                const Divider(height: 1),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  Widget _buildComposer(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _loading ? null : _add,
                style: EmphasisButton.borderEmphasis(
                  context,
                  color: Colors.green,
                ),
                child: const Text('+'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in _topics)
                  KvTopicChip(
                    label: t,
                    onTap: () => _applyTopicChip(t),
                    onDelete: () => _deleteTopic(t),
                  ),
                KvAddTopicChip(onTap: _addTopic),
              ],
            ),
          ),
          const SizedBox(height: 8),
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

  Widget _buildList() {
    final list = _tab == 0 ? _open : _done;
    final isOpen = _tab == 0;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isOpen ? '暂无待办任务' : '暂无已完成任务',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final task = list[i];
        return KvTaskCard(
          task: task,
          isOpen: isOpen,
          onDone: isOpen ? () => _markDone(task) : null,
          onEdit: () => _editTask(task, isDone: !isOpen),
          onDelete: () => _deleteTask(task, isDone: !isOpen),
        );
      },
    );
  }
}

// ── 注册 ──────────────────────────────────────────────────────────────────

void registerKvcliTodoDemo() {
  demoRegistry.register(KvcliTodoDemo());
}
