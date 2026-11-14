// nx-kv 任务正文的解析：轮次 callout 的格式**不是这里的发明**，
// 它是服务端 `src/shared/feedback-text.ts` 写进正文的固定形状：
//
//   > [!WARNING] 第 N 轮 · 验收反馈
//   > ...
//   > [!NOTE] 第 N 轮 · 完成总结
//
// 所以这些用例里的样例都是**真任务的正文**（#200 那条），而不是手编的理想输入：
// 认错格式的后果是详情页把反馈当正文显示、或者轮次时间线少一轮。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_md.dart';

const _realTask = '''---
board: b_mwezoy8qnl3p7
project: github.com/on-devplan/nx-kv
boardIntro: ref:ref_159b5c1d79183038
---
# 调研一下

## 背景

1.当前的action可以派发cli和http

## 验收

- [ ] …

> [!NOTE] 第 1 轮 · 完成总结
> 调研完成并给出可跑的最小案例。

> [!WARNING] 第 1 轮 · 验收反馈
> **给出设计方案**

> [!NOTE] 第 2 轮 · 完成总结
> 第 2 轮：按验收反馈交付设计方案。

> [!WARNING] 第 2 轮 · 验收反馈
> **调研二阶段：**
>
> **针对契约当前已经实施**

—— 历史轮次（已按最新反馈推进，仅供追溯）——
· 第 1 轮 反馈「给出设计方案」
''';

void main() {
  test('frontmatter 被切掉，正文从标题开始', () {
    final (fm, body) = splitFrontmatter(_realTask);
    expect(fm, contains('board: b_mwezoy8qnl3p7'));
    expect(body.startsWith('# 调研一下'), isTrue);
    expect(body.contains('board:'), isFalse);
  });

  test('没有 frontmatter 时不误伤正文', () {
    final (fm, body) = splitFrontmatter('# 标题\n正文');
    expect(fm, isEmpty);
    expect(body, '# 标题\n正文');
  });

  test('轮次按出现顺序解析，kind 区分反馈与总结', () {
    final rounds = extractRounds(_realTask);
    expect(rounds.length, 4);
    expect(rounds.map((r) => r.index).toList(), [1, 1, 2, 2]);
    expect(rounds.map((r) => r.isFeedback).toList(), [false, true, false, true]);
    expect(rounds[1].body, '**给出设计方案**');
    expect(rounds[3].label, '验收反馈');
  });

  test('callout 的续行（含空 > 行）都要进这一轮，不能截断', () {
    final rounds = extractRounds(_realTask);
    expect(rounds[3].body, contains('调研二阶段：'));
    expect(rounds[3].body, contains('针对契约当前已经实施'));
  });

  test('正文去掉轮次后不再复述反馈，但保留任务本身的内容', () {
    final body = bodyWithoutRounds(_realTask);
    expect(body, contains('## 背景'));
    expect(body, contains('- [ ] …'));
    expect(body.contains('调研完成并给出可跑的最小案例'), isFalse);
    expect(body.contains('给出设计方案'), isFalse);
  });

  test('没有 callout 的正文原样返回（含 frontmatter 也不动）', () {
    const plain = '# 甲\n\n正文一段。\n';
    expect(bodyWithoutRounds(plain), plain);
  });

  test('标题优先取 # 标题行，超长截断', () {
    expect(titleOf(_realTask), '调研一下');
    expect(titleOf('没有标题的一段\n第二行'), '没有标题的一段');
    expect(titleOf(''), '(无标题)');
    expect(titleOf('# ${'x' * 200}').endsWith('…'), isTrue);
  });

  test('纯文本化：去掉标记但保留句子', () {
    expect(plainText('## 背景\n- 甲乙\n> 引用'), '背景\n甲乙\n引用');
  });

  test('耗时格式化', () {
    expect(humanDuration(null), '—');
    expect(humanDuration(35), '35s');
    expect(humanDuration(45 * 60), '45m');
    expect(humanDuration(2 * 3600 + 18 * 60), '2h 18m');
  });

  test('时间戳：空串给破折号，正常串能算出相对时间', () {
    expect(humanTime(''), '—');
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';
    expect(humanTime(stamp), '刚刚');
  });
}
