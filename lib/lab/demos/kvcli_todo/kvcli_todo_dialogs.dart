// KV 清单 —— 弹窗（编辑 / 删除确认 / 完成结果 / 添加快捷 topic）。

import 'package:flutter/material.dart';

import '../../../core/design/emphasis_button.dart';
import 'kvcli_todo_models.dart';

/// 编辑结果：open 任务可改 topic+text；done 任务可改 text+note。
typedef KvEditResult = ({String topic, String text, String note});

/// 标记完成：输入完成结果（可选），返回 null 表示取消。
Future<String?> showKvDoneResultDialog(BuildContext context, KvTask task) async {
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

/// 编辑任务。isDone 时改 text+note（topic 保留）；否则改 topic+text（note 保留）。
Future<KvEditResult?> showKvTaskEditDialog(
  BuildContext context, {
  required KvTask task,
  required bool isDone,
}) async {
  final topicCtrl = TextEditingController(text: task.topic);
  final textCtrl = TextEditingController(text: task.text);
  final noteCtrl = TextEditingController(text: task.note);

  final result = await showDialog<KvEditResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('编辑 #${task.id}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDone) ...[
              TextField(
                controller: topicCtrl,
                decoration: const InputDecoration(
                  labelText: '主题 (--topic)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: textCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '任务文本',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (isDone) ...[
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: '完成结果 note',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(
            ctx,
            (
              topic: isDone ? task.topic : topicCtrl.text.trim(),
              text: textCtrl.text.trim(),
              note: isDone ? noteCtrl.text.trim() : task.note,
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  topicCtrl.dispose();
  textCtrl.dispose();
  noteCtrl.dispose();
  return result;
}

/// 确认单条删除，返回是否确认。
Future<bool> showKvTaskDeleteConfirm(BuildContext context, KvTask task) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除任务？'),
      content: Text(
        '#${task.id} ${task.topic}\n${task.text}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: EmphasisButton.dangerEmphasis(context),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 添加快捷 topic，返回新增的 topic 名（已 trim），空串 / 取消返回 null。
Future<String?> showKvAddTopicDialog(
  BuildContext context, {
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('添加快捷 topic'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '主题 (--topic)',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('添加'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}
