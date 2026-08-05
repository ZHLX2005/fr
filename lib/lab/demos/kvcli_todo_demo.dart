// kvcli todo 行为模拟 — 调真实 GoFrame 后端的 /api/v1/kv 端点，
// 与 `lab/kvcli` CLI 端共享同一份存储（key: todo:open / todo:done）。
//
// 真实链路：
//   - set  : POST /api/v1/kv  body={key,value,tags,visibility,ttl}  value 为 Task[] JSON
//   - get  : GET  /api/v1/kv/{key}                                解析 KvItem.value
//   - 找不到 key 时视为空数组（与 kvcli internal/todo/todo.go load 行为一致）
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

// ── 数据模型 ──────────────────────────────────────────────────────────────

class _Task {
  const _Task({
    required this.id,
    required this.topic,
    required this.text,
    required this.createdAt,
    this.doneAt = '',
    this.note = '',
  });

  final int id;
  final String topic;
  final String text;
  final String createdAt;
  final String doneAt;
  final String note;

  _Task copyWith({String doneAt = '', String note = ''}) => _Task(
        id: id,
        topic: topic,
        text: text,
        createdAt: createdAt,
        doneAt: doneAt,
        note: note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'text': text,
        'createdAt': createdAt,
        'doneAt': doneAt,
        'note': note,
      };

  static _Task fromJson(Map<String, dynamic> j) => _Task(
        id: (j['id'] as num).toInt(),
        topic: j['topic'] as String? ?? '',
        text: j['text'] as String? ?? '',
        createdAt: j['createdAt'] as String? ?? '',
        doneAt: j['doneAt'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

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
  static const String _kOpen = 'todo:open';
  static const String _kDone = 'todo:done';

  final _topicCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();

  List<_Task> _open = const [];
  List<_Task> _done = const [];
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

  Future<List<_Task>> _readKey(String key) async {
    final res = await widget.kv.get(key);
    // key 不存在 / 后端返回失败：当作空数组
    if (!res.isSuccess || res.data == null) return const <_Task>[];
    final raw = res.data!.value.trim();
    if (raw.isEmpty) return const <_Task>[];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(_Task.fromJson).toList();
    } catch (_) {
      // 解析失败不阻塞 UI，留 debugPrint 排查
      debugPrint('kvcli_todo: parse $key failed, fallback to []');
      return const <_Task>[];
    }
  }

  Future<void> _writeKey(String key, List<_Task> tasks) async {
    final raw = jsonEncode(tasks.map((t) => t.toJson()).toList());
    final res = await widget.kv.set(key: key, value: raw, ttl: 0);
    if (!res.isSuccess) {
      throw Exception('写 $key 失败: code=${res.code} ${res.message}');
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final open = await _readKey(_kOpen);
      final done = await _readKey(_kDone);
      if (!mounted) return;
      setState(() {
        _open = open;
        _done = done;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('读取失败：${_errMsg(e)}');
    }
  }

  // 主题去重 + 按出现频次倒序，取前 8 个作为 Chip 行
  List<String> _recentTopics() {
    final counter = <String, int>{};
    for (final t in _open) {
      counter[t.topic] = (counter[t.topic] ?? 0) + 1;
    }
    for (final t in _done) {
      counter[t.topic] = (counter[t.topic] ?? 0) + 1;
    }
    final list = counter.entries.where((e) => e.key.trim().isNotEmpty).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(8).map((e) => e.key).toList();
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
    final task = _Task(
      id: maxId + 1,
      topic: topic,
      text: text,
      createdAt: DateTime.now().toIso8601String(),
    );
    final next = [..._open, task];
    try {
      await _writeKey(_kOpen, next);
    } catch (e) {
      _toast('提交失败：${_errMsg(e)}');
      return;
    }
    if (!mounted) return;
    setState(() => _open = next);
    _textCtrl.clear();
    _textFocus.requestFocus();
  }

  Future<void> _markDone(_Task task) async {
    final note = await _promptDoneResult(task);
    if (note == null) return; // 用户取消

    final completed = task.copyWith(
      doneAt: DateTime.now().toIso8601String(),
      note: note,
    );
    final open = _open.where((t) => t.id != task.id).toList();
    final done = [..._done, completed];
    try {
      await _writeKey(_kOpen, open);
      await _writeKey(_kDone, done);
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

  Future<String?> _promptDoneResult(_Task task) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('完成 #${task.id}：${task.text}'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '完成结果（可选）',
            border: OutlineInputBorder(),
            hintText: '留空直接提交',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('标记完成'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
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
      await widget.kv.delete(_kOpen);
      await widget.kv.delete(_kDone);
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
    final recent = _recentTopics();

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
                _TabChip(
                  label: '待办 (${_open.length})',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                _TabChip(
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
                _buildComposer(scheme, recent),
                const Divider(height: 1),
                Expanded(child: _buildList()),
              ],
            ),
    );
  }

  Widget _buildComposer(ColorScheme scheme, List<String> recent) {
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
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in recent)
                    _TopicChip(
                      label: t,
                      onTap: () => _applyTopicChip(t),
                    ),
                ],
              ),
            ),
          ],
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
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _tab == 0 ? '暂无待办任务' : '暂无已完成任务',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: list.length,
      itemBuilder: (context, i) => _TaskCard(
        task: list[i],
        isOpen: _tab == 0,
        onDone: _tab == 0 ? () => _markDone(list[i]) : null,
      ),
    );
  }
}

// ── 子组件 ────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.primary : scheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: selected ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: selected ? 0.5 : 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isOpen,
    this.onDone,
  });

  final _Task task;
  final bool isOpen;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${task.id}',
                        style: TextStyle(
                          color: scheme.outline,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task.topic,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.text,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOpen
                        ? '创建于 ${task.createdAt}'
                        : '完成于 ${task.doneAt}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                  if (!isOpen && task.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'note: ${task.note}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDone != null)
              OutlinedButton.icon(
                onPressed: onDone,
                style: EmphasisButton.borderEmphasis(
                  context,
                  color: Colors.blue,
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('完成'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 注册 ──────────────────────────────────────────────────────────────────

void registerKvcliTodoDemo() {
  demoRegistry.register(KvcliTodoDemo());
}