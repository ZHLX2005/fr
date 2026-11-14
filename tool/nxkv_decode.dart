// 契约生成物的**离线解码回归**：不需要网络、不需要 nx-kv 在跑。
//
// 抓的是真响应（`tool/fixtures/*.json`，来自本机 0.54.0 服务），
// 用生成客户端走一遍解码 —— 专门盯「可选字段 / null / 附件」这些在
// 运行期才会炸的地方：
//
//   · `pickupSec` 未领取时是 null
//   · `attachments` 在没有附件时整个字段缺失（服务端 fail-open）
//   · 详情里的 `text` 是可能带 frontmatter 的 md
//
// 为什么不用 flutter test：这条链路是纯 Dart（`nx_kv_client` 零 flutter 依赖），
// 用 `dart run` 就能跑，比 widget test 快一个数量级，也不会被 flutter_tester 卡住。
//
// 用法：
//   dart run tool/nxkv_decode.dart            # 用 tool/fixtures
//   dart run tool/nxkv_decode.dart <fixtures> # 指定目录
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:nx_kv_client/nx_kv_client.dart' as kv;

int _checks = 0;
int _failed = 0;

void _ok(String what, bool cond, [String? detail]) {
  _checks++;
  if (!cond) _failed++;
  print('${cond ? '  ✓' : '  ✗'} $what${cond || detail == null ? '' : ' —— $detail'}');
}

Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty ? args.first : 'tool/fixtures';

  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('$dir/$name.json').readAsStringSync()) as Map<String, dynamic>;

  final byPath = <String, Map<String, dynamic>>{
    '/api/contract': fixture('contract'),
    '/api/localtasks': fixture('localtasks'),
    '/api/localtasks/tasks': fixture('tasks'),
    '/api/localtasks/item': fixture('item'),
  };

  final sizes = {
    for (final e in byPath.entries) e.key: e.value.toString().length,
  };

  final client = kv.NxKvClientApi((method, path, query, body) async {
    final hit = byPath[path];
    if (hit == null) throw StateError('样本里没有 $method $path');
    return hit;
  });

  print('样本      $dir');
  print('端侧契约  ${kv.contractHash}（nx-kv ${kv.contractVersion}）');

  // ── 契约 ────────────────────────────────────────────────
  final contract = await client.systemContract();
  print('\n契约      ${contract.actions.length} 条 action');
  _ok('服务端指纹与生成物一致（${contract.hash}）', contract.hash == kv.contractHash);
  final ids = contract.actions.map((a) => a.id).toSet();
  for (final need in const [
    'localtask.list',
    'localtask.tasks',
    'localtask.get',
    'localtask.claim',
    'localtask.done',
    'localtask.reopen',
    'localtask.add',
  ]) {
    _ok('契约里有 $need', ids.contains(need));
  }

  // ── 主题清单 ────────────────────────────────────────────
  final list = await client.localtaskList();
  print('\n主题      ${list.topics.length} 个 · 等待中 ${list.waiting}');
  _ok('主题解析出计数', list.topics.isNotEmpty && list.topics.every((t) => t.total >= 0));
  _ok('settings 解析出超时', list.settings.timeoutSec > 0);
  final withWork = list.topics.where((t) => t.total > 0).toList();
  if (withWork.isEmpty) {
    print('（样本里没有带任务的主题，后续跳过）');
    return;
  }
  final topic = withWork.first;

  // ── 一个主题的清单 ──────────────────────────────────────
  final tasks = await client.localtaskTasks(topic.key, null, null);
  print('\n清单      ${tasks.name} · ${tasks.tasks.length}/${tasks.total} 条');
  _ok('清单条数与 total 一致', tasks.tasks.length == tasks.total);
  _ok('每行都有编号与标题', tasks.tasks.every((t) => t.id > 0 && t.title.isNotEmpty));
  _ok('标题里不含 frontmatter 的 key', tasks.tasks.every((t) => !t.title.startsWith('board:')));

  // ── 详情 ────────────────────────────────────────────────
  final row = tasks.tasks.first;
  final task = await client.localtaskGet(row.id, null, topic.key);
  print('\n详情      #${task.id} ${task.status} · 第 ${task.round} 轮 · '
      '正文 ${task.text.length} 字 · 附件 ${task.attachments?.length ?? 0} 个');
  _ok('详情编号与清单一致', task.id == row.id);
  _ok('正文不是空的', task.text.trim().isNotEmpty);
  _ok('状态是已知取值',
      const ['pending', 'claimed', 'done', 'cancelled'].contains(task.status),
      task.status);
  _ok('可选字段允许为 null（pickupSec）', task.pickupSec == null || task.pickupSec! >= 0);
  for (final a in task.attachments ?? const <kv.LocaltaskGetAttachment>[]) {
    _ok('附件「${a.name}」有种类与大小文案', a.kind.isNotEmpty && a.sizeText.isNotEmpty);
  }

  // ── 代价对比：为什么不给 localtask.list 加 tasks ────────────
  print('\n体积对比  清单总览 ${(sizes['/api/localtasks']! / 1024).toStringAsFixed(0)} KB'
      ' · 单主题清单 ${(sizes['/api/localtasks/tasks']! / 1024).toStringAsFixed(0)} KB'
      ' · 详情 ${(sizes['/api/localtasks/item']! / 1024).toStringAsFixed(0)} KB');

  print('\n${_failed == 0 ? '全部通过' : '有 $_failed 项失败'}（共 $_checks 项断言）');
  if (_failed > 0) exitCode = 1;
}
