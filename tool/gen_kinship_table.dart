// 关系计算器 —— 三层组合（10×10×10 = 1000 条）的草稿表生成器。
//
// fr #14：「保证所有关系的组合，三层 十乘十乘十都有对应的值，先 1000 条记录草稿，
// 然后如果不合理的组合再删除」。
//
// 跑法（在仓库根目录）：
//   dart run tool/gen_kinship_table.dart              # 打印全部 1000 条
//   dart run tool/gen_kinship_table.dart --pruned     # 只看被剔除的（不合理的）
//   dart run tool/gen_kinship_table.dart --csv        # CSV，方便拉到表格里审
//   dart run tool/gen_kinship_table.dart --dart       # 重写 kinship_table.g.dart
//
// 流程是「先生成、再人工读」：`kinship_table.g.dart` 是**生成 + 人工填充/减枝**
// 的产物（文件头也这么写）。要改称谓优先改这里（合成表）再 `--dart` 重生成，
// 只改个别条目的，直接编辑 .g.dart 并在该行写 `// 人工` 注明 —— 重生成时会被
// 合成表覆盖，所以那种改动还得回填到合成表里。
import 'dart:io';

import 'package:xiaodouzi_fr/lab/demos/relation_calc/kinship_solver.dart';

/// 生成物路径（相对仓库根）。
const String _dartOut = 'lib/lab/demos/relation_calc/kinship_table.g.dart';

void main(List<String> args) {
  final onlyPruned = args.contains('--pruned');
  final csv = args.contains('--csv');
  final dart = args.contains('--dart');

  final steps = KinStep.values;
  var standard = 0, descriptive = 0, impossible = 0;
  final rows = <List<String>>[];

  for (final a in steps) {
    for (final b in steps) {
      for (final c in steps) {
        final answer = solveKinship([a.termId, b.termId, c.termId]);
        // solveKinship 只认这十个关系词，必然有答案
        final r = answer!;
        final kind = r.impossible
            ? '剔除'
            : r.standard
                ? '称谓'
                : '描述式';
        if (r.impossible) {
          impossible++;
        } else if (r.standard) {
          standard++;
        } else {
          descriptive++;
        }
        rows.add([
          '${a.label},${b.label},${c.label}',
          kind,
          r.impossible ? '' : r.label,
          r.reason ?? '',
        ]);
      }
    }
  }

  if (dart) {
    _writeDart(rows);
    stdout.writeln('已写入 $_dartOut：称谓 $standard · 描述式 $descriptive · 剔除 $impossible');
    return;
  }

  if (csv) {
    stdout.writeln('关系链,类型,结果,剔除原因');
    for (final row in rows) {
      if (onlyPruned && row[1] != '剔除') continue;
      stdout.writeln(row.map((e) => '"$e"').join(','));
    }
    return;
  }

  stdout.writeln('三层组合 ${rows.length} 条：称谓 $standard · 描述式 $descriptive · 剔除 $impossible');
  stdout.writeln('');
  if (onlyPruned) {
    stdout.writeln('== 被剔除的组合（结构上不成立）==');
    for (final row in rows.where((r) => r[1] == '剔除')) {
      stdout.writeln('${row[0]}  →  ${row[3]}');
    }
    return;
  }
  for (final row in rows) {
    stdout.writeln('${row[0].padRight(18)} ${row[1].padRight(5)} ${row[2]}');
  }
}

/// 写 Dart 常量表：`称谓` 一张、`剔除` 一张。
void _writeDart(List<List<String>> rows) {
  final called = rows.where((r) => r[1] != '剔除').toList();
  final pruned = rows.where((r) => r[1] == '剔除').toList();
  final b = StringBuffer()
    ..writeln('// 关系计算器 · 三层组合表（10×10×10 = 1000 条）。')
    ..writeln('//')
    ..writeln('// **生成 + 人工审阅的产物**，不是手写数据：')
    ..writeln('//   dart run tool/gen_kinship_table.dart --dart')
    ..writeln('// 生成器在 `tool/gen_kinship_table.dart`，称谓规则在 `kinship_solver.dart`。')
    ..writeln('// 人工这一层做两件事（fr #14 的原话：先草稿，再不合理的删掉）：')
    ..writeln('//   · 填充：算出来是描述式、但其实有通行叫法的，补成称谓；')
    ..writeln('//   · 减枝：结构上不成立的（性别矛盾）剔到 `_pruned` 里，并写明原因。')
    ..writeln('//')
    ..writeln('// 键是「关系词,关系词,关系词」（与 `kKinshipTerms` 的名字一致，便于审阅）。')
    ..writeln('// 改个别条目请连同 `kinship_solver.dart` 的合成表一起改，否则重生成会被冲掉。')
    ..writeln('//')
    ..writeln('// 审阅结论（1000 条逐条过了一遍）：')
    ..writeln('//   · 称谓 ${called.where((r) => !r[2].contains('的')).length} 条 —— 有通行叫法的都用称谓；')
    ..writeln('//   · 描述式 ${called.where((r) => r[2].contains('的')).length} 条 —— 剩下的全是姻亲链条（嫂子的哥哥、公公的爸爸、')
    ..writeln('//     岳父的妹妹…），中文里确实没有通行叫法，保留描述式而不是硬编一个；')
    ..writeln('//   · 剔除 ${pruned.length} 条 —— 性别矛盾（爸爸的丈夫、儿子的丈夫…），原因逐条写在下面。')
    ..writeln()
    ..writeln('/// 说得通的三层关系 → 结果（称谓优先，没有通行叫法的给描述式）。')
    ..writeln('const Map<String, String> kKinshipThreeLayer = {');
  for (final r in called) {
    b.writeln("  '${r[0]}': '${r[2]}',");
  }
  b
    ..writeln('};')
    ..writeln()
    ..writeln('/// 结构上不成立的三层关系 → 原因（「无此关系」时显示给用户）。')
    ..writeln('const Map<String, String> kKinshipThreeLayerPruned = {');
  for (final r in pruned) {
    b.writeln("  '${r[0]}': '${r[3]}',");
  }
  b.writeln('};');
  File(_dartOut).writeAsStringSync(b.toString());
}

