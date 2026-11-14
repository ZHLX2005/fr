// 任务正文的 markdown 小工具：没有一份「nx-kv 专用 markdown」——它就是普通 md，
// 只是约定里有两样东西值得单独认出来：
//
//   · frontmatter（`---` 之间）：board / project / 介绍引用，属于元数据，正文里不该显示；
//   · 轮次 callout（`> [!WARNING] 第 N 轮 · 验收反馈`）：nx-kv 写反馈时的固定格式
//     （服务端 `src/shared/feedback-text.ts` 是唯一出处），端侧照它的样子读，
//     不自己发明解析规则。
//
// 解析放这里而不是页面里：详情页要按轮次画时间线，新建/反馈的编辑器要预览，
// 两处都得是同一套「什么叫一轮」。
import 'package:flutter/foundation.dart';

/// 一轮反馈 / 总结。
@immutable
class NxKvRound {
  const NxKvRound({
    required this.index,
    required this.label,
    required this.kind,
    required this.body,
  });

  /// 轮次号（正文里写的那个 N）。
  final int index;

  /// callout 标题里的说明（`验收反馈` / `完成总结` …）。
  final String label;

  /// `warning`（反馈）或 `note`（总结）。
  final String kind;

  /// 这一轮的内容（callout 的正文行，已去掉 `>` 前缀）。
  final String body;

  bool get isFeedback => kind == 'warning';
}

final RegExp _kCallout = RegExp(
  r'^>\s*\[!(WARNING|NOTE|TIP|IMPORTANT)\]\s*第\s*(\d+)\s*轮\s*[·:：]\s*(.+)$',
);

/// 拆 frontmatter：返回 (元数据行, 正文)。
///
/// 只做「切掉第一段被 `---` 包起来的部分」，不做 YAML 解析 —— 端侧目前只用到
/// 「有没有 frontmatter」，把 key 也解出来反而要维护一份 YAML 子集。
(String frontmatter, String body) splitFrontmatter(String source) {
  final text = source.replaceAll('\r\n', '\n');
  if (!text.startsWith('---')) return ('', text);
  final end = text.indexOf('\n---', 3);
  if (end < 0) return ('', text);
  final after = text.indexOf('\n', end + 1);
  return (text.substring(4, end), after < 0 ? '' : text.substring(after + 1));
}

/// 正文里的轮次时间线（按出现顺序）。没有 callout 就是空列表。
List<NxKvRound> extractRounds(String source) {
  final (_, body) = splitFrontmatter(source);
  final lines = body.split('\n');
  final rounds = <NxKvRound>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _kCallout.firstMatch(lines[i].trim());
    if (m == null) continue;
    final buf = <String>[];
    var j = i + 1;
    while (j < lines.length) {
      final line = lines[j];
      final t = line.trimLeft();
      // callout 的续行必须以 '>' 开头；遇到空行（或 '>') 也继续吃掉，
      // 直到出现第一行不是 '>' 的正文为止
      if (t.startsWith('>')) {
        buf.add(t.replaceFirst(RegExp(r'^>\s?'), ''));
        j++;
        continue;
      }
      if (t.isEmpty && j + 1 < lines.length && lines[j + 1].trimLeft().startsWith('>')) {
        buf.add('');
        j++;
        continue;
      }
      break;
    }
    rounds.add(NxKvRound(
      index: int.tryParse(m.group(2) ?? '') ?? rounds.length + 1,
      label: (m.group(3) ?? '').trim(),
      kind: (m.group(1) ?? 'note').toLowerCase(),
      body: buf.join('\n').trim(),
    ));
    i = j;
  }
  return rounds;
}

/// 正文里**去掉**轮次 callout 之后的部分（详情页的「正文」不该把反馈再复述一遍）。
String bodyWithoutRounds(String source) {
  final (fm, body) = splitFrontmatter(source);
  if (fm.isEmpty && !body.contains('[!')) return source.replaceAll('\r\n', '\n');
  final out = <String>[];
  var skipping = false;
  for (final line in body.split('\n')) {
    final t = line.trimLeft();
    if (_kCallout.hasMatch(t)) {
      skipping = true;
      continue;
    }
    if (skipping) {
      if (t.startsWith('>')) continue;
      if (t.isEmpty) continue;
      skipping = false;
    }
    out.add(line);
  }
  return out.join('\n').trim();
}

/// 取标题：跳过 frontmatter，首个 `#` 标题优先，否则首行。
String titleOf(String source, {int max = 80}) {
  final (_, body) = splitFrontmatter(source);
  final lines = body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return '(无标题)';
  final heading = lines.firstWhere((l) => RegExp(r'^#{1,6}\s+').hasMatch(l), orElse: () => lines.first);
  final title = heading.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
  return title.length > max ? '${title.substring(0, max)}…' : title;
}

/// 一段 markdown 的纯文本（给「引用评价」的锚点用）。
String plainText(String md) {
  var s = md;
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  s = s.replaceAll('**', '').replaceAll('`', '');
  return s.trim();
}

/// 时间戳（`2026-11-14 07:07:05`）→ 人话。
///
/// 服务端给的是**本机时区的字符串**，不是 ISO8601 —— 端侧不猜时区，
/// 只按原样显示；要算「多久之前」才解析成本地时间。
String humanTime(String stamp) {
  if (stamp.trim().isEmpty) return '—';
  final dt = DateTime.tryParse(stamp.replaceFirst(' ', 'T'));
  if (dt == null) return stamp;
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return stamp.split(' ').first;
}

/// 秒数 → `2h 18m` / `45m` / `30s`。
String humanDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '—';
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}';
}
