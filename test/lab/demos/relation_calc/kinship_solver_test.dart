// 关系计算器的结构推导（fr #14）。
//
// 反馈原话：「保证所有关系的组合，三层 十乘十乘十都有对应的值，先 1000 条记录
// 草稿，然后如果不合理的组合再删除」。所以这里钉三件事：
//   1. **1000 条全覆盖**：每条要么给得出值（称谓或描述式），要么明确剔除 + 原因；
//   2. **剔除的只有不成立的**：性别矛盾（爸爸的丈夫），不是「我没配规则」；
//   3. 常用链路的答案与预设 `kinship_preset.dart` 的 note 口径一致。
//
// 草稿表本身不手写：`dart run tool/gen_kinship_table.dart` 从这套逻辑生成，
// 要审阅就重跑脚本（`--pruned` 只看剔除项）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/calc_view.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/kinship_preset.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/kinship_solver.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/kinship_table.g.dart';

String _answer(List<KinStep> steps) =>
    solveKinship(steps.map((s) => s.termId).toList())!.label;

void main() {
  group('覆盖：三层组合 10×10×10 全部有交代', () {
    test('每条要么有值，要么被剔除且说明原因', () {
      var named = 0, described = 0, pruned = 0;
      var missing = 0, unexplained = 0;
      for (final a in KinStep.values) {
        for (final b in KinStep.values) {
          for (final c in KinStep.values) {
            final r = solveKinship([a.termId, b.termId, c.termId])!;
            if (r.impossible) {
              pruned++;
              if ((r.reason ?? '').isEmpty) unexplained++;
            } else if (r.label.isEmpty) {
              missing++;
            } else if (r.standard) {
              named++;
            } else {
              described++;
            }
          }
        }
      }
      expect(named + described + pruned, 1000);
      expect(missing, 0, reason: '有组合算不出值 —— 这就是「无法计算」的老毛病');
      expect(unexplained, 0, reason: '剔除必须说清为什么');
      // 口径守住：至少八成是通行称谓，剔除的都是真不成立的那批
      expect(named, greaterThan(600));
      expect(pruned, lessThan(250));
    });

    test('剔除原因指向性别矛盾，而不是「没有规则」', () {
      final r = solveKinship(['t_father', 't_husband'])!;
      expect(r.impossible, isTrue);
      expect(r.reason, contains('男性'));
      expect(r.reason, contains('丈夫'));
    });
  });

  group('常用链路：称谓与预设的 note 口径一致', () {
    test('妈妈的爸爸的姐姐 = 姑婆（预设：外公的姐妹）', () {
      expect(_answer([KinStep.mother, KinStep.father, KinStep.elderSister]), '姑婆');
    });

    test('爸爸的哥哥的妻子 = 伯母（预设：伯父的妻子）', () {
      expect(_answer([KinStep.father, KinStep.elderBrother, KinStep.wife]), '伯母');
    });

    test('爷爷的哥哥 = 伯公、奶奶的哥哥 = 舅公（预设同名不同源）', () {
      expect(_answer([KinStep.father, KinStep.father, KinStep.elderBrother]), '伯公');
      expect(_answer([KinStep.father, KinStep.mother, KinStep.elderBrother]), '舅公');
    });

    test('姻亲：妻子的妹妹的丈夫 = 连襟、丈夫的哥哥的妻子 = 妯娌', () {
      expect(_answer([KinStep.wife, KinStep.youngerSister, KinStep.husband]), '连襟');
      expect(_answer([KinStep.husband, KinStep.elderBrother, KinStep.wife]), '妯娌');
    });

    test('亲家：儿媳的妈妈、女婿的爸爸', () {
      expect(_answer([KinStep.son, KinStep.wife, KinStep.mother]), '亲家母');
      expect(_answer([KinStep.daughter, KinStep.husband, KinStep.father]), '亲家公');
    });
  });

  group('化简与两读法', () {
    test('配偶抵消：妻子的丈夫 = 我、丈夫的妻子 = 我', () {
      expect(_answer([KinStep.wife, KinStep.husband]), '我');
      expect(_answer([KinStep.husband, KinStep.wife]), '我');
    });

    test('爸爸的妻子 = 妈妈（不是「描述式」）', () {
      final r = solveKinship(['t_father', 't_wife'])!;
      expect(r.label, '妈妈');
      expect(r.standard, isTrue);
    });

    test('儿子的爸爸两读：我给不出唯一解，就两个都写出来', () {
      expect(_answer([KinStep.son, KinStep.father]), '我／丈夫');
    });

    test('没有通行叫法的关系给描述式，而不是「无法计算」', () {
      final r = solveKinship(['t_elder_brother', 't_wife', 't_father'])!; // 嫂子的爸爸
      expect(r.impossible, isFalse);
      expect(r.standard, isFalse);
      expect(r.label, contains('的'));
    });
  });

  group('不认识的关系词交回关系库', () {
    test('自定义关系词返回 null', () {
      expect(solveKinship(['t_boss']), isNull);
    });
  });

  group('三层组合表（生成 + 人工审阅的那份）', () {
    test('1000 = 有值的 + 剔除的，一条不漏', () {
      expect(kKinshipThreeLayer.length + kKinshipThreeLayerPruned.length, 1000);
    });

    test('有值的条目都有内容；剔除的条目都写了原因', () {
      expect(kKinshipThreeLayer.values.where((v) => v.trim().isEmpty), isEmpty);
      expect(
        kKinshipThreeLayerPruned.values.where((v) => v.trim().isEmpty),
        isEmpty,
        reason: '剔除必须说清为什么，否则用户只看到「无此关系」',
      );
    });

    test('键都是三个关系词，且都在十个基础关系词里', () {
      final allowed = KinStep.values.map((s) => s.label).toSet();
      for (final key in [
        ...kKinshipThreeLayer.keys,
        ...kKinshipThreeLayerPruned.keys,
      ]) {
        final parts = key.split(',');
        expect(parts, hasLength(3), reason: key);
        for (final p in parts) {
          expect(allowed, contains(p), reason: key);
        }
      }
    });

    test('抽样：截图里那条链与几个典型', () {
      // 反馈截图：我 → 妈妈 → 爸爸 → 姐姐（以前是「无法计算」）
      expect(kKinshipThreeLayer['妈妈,爸爸,姐姐'], '姑婆');
      expect(kKinshipThreeLayer['爸爸,哥哥,妻子'], '伯母');
      expect(kKinshipThreeLayer['妻子,妹妹,丈夫'], '连襟');
      // 剔除项给的是原因，不是空字符串
      expect(kKinshipThreeLayerPruned['爸爸,爸爸,丈夫'], contains('男性'));
      expect(kKinshipThreeLayerPruned['妈妈,妈妈,妻子'], contains('女性'));
      // 表只管三层：两层不该出现在这里（那部分走关系库/现场推）
      expect(kKinshipThreeLayer['儿子的爸爸'], isNull);
    });
  });

  group('计算页：规则库没配到也不再说「无法计算」', () {
    testWidgets('我 → 妈妈 → 爸爸 → 姐姐 得「姑婆」', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: CalcView(data: kinshipPresetData())),
      ));
      await tester.pumpAndSettle();

      // 关系词盘上的按钮：点三下（妈妈 → 爸爸 → 姐姐）
      Future<void> tapTerm(String name) async {
        await tester.tap(find.widgetWithText(OutlinedButton, name).first);
        await tester.pump();
      }

      await tapTerm('妈妈');
      await tapTerm('爸爸');
      await tapTerm('姐姐');

      expect(find.text('姑婆'), findsOneWidget);
      expect(find.text('无法计算'), findsNothing);
    });
  });
}
