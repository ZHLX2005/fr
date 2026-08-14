// 通用关系计算引擎单测 —— 覆盖链式计算、无限嵌套、无解降级、自定义领域。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/kinship_preset.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/relation_calc_models.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/relation_engine.dart';

void main() {
  group('亲戚预设链式计算', () {
    final engine = RelationEngine(kinshipPresetData());
    final me = engine.entityById['e_me']!;
    String tid(String name) =>
        engine.graph.terms.firstWhere((t) => t.name == name).id;
    String eid(String name) =>
        engine.graph.entities.firstWhere((e) => e.name == name).id;

    test('我 + 爸爸 = 爸爸', () {
      final r = engine.resolve(me.id, [tid('爸爸')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '爸爸');
    });

    test('爸爸 + 爸爸 = 爷爷', () {
      final r = engine.resolve(me.id, [tid('爸爸'), tid('爸爸')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '爷爷');
    });

    test('无限嵌套：爸爸 × 3 = 太爷爷', () {
      final r = engine.resolve(me.id, [tid('爸爸'), tid('爸爸'), tid('爸爸')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '太爷爷');
    });

    test('妈妈 + 妈妈 = 外婆', () {
      final r = engine.resolve(me.id, [tid('妈妈'), tid('妈妈')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '外婆');
    });

    test('妈妈 + 哥哥 = 舅舅', () {
      final r = engine.resolve(me.id, [tid('妈妈'), tid('哥哥')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '舅舅');
    });

    test('爸爸 + 姐姐 = 姑妈', () {
      final r = engine.resolve(me.id, [tid('爸爸'), tid('姐姐')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '姑妈');
    });

    test('哥哥 + 儿子 = 侄子', () {
      final r = engine.resolve(eid('哥哥'), [tid('儿子')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '侄子');
    });

    test('姐姐 + 女儿 = 外甥女', () {
      final r = engine.resolve(eid('姐姐'), [tid('女儿')]);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '外甥女');
    });

    test('空链：success=true 且停在起点', () {
      final r = engine.resolve(me.id, []);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '我');
      expect(r.steps, isEmpty);
    });
  });

  group('无解降级', () {
    final engine = RelationEngine(kinshipPresetData());
    final me = engine.entityById['e_me']!;

    test('中间步无规则 → failedIndex 指向失败步，steps 只含成功前缀', () {
      // 预设无「妈妈 的 哥哥 的 姐姐」链路中的某段：
      // 妈妈+哥哥=舅舅 成功，舅舅+妹妹 无规则 → 失败在第 2 步。
      final tidMother =
          engine.graph.terms.firstWhere((t) => t.name == '妈妈').id;
      final tidBro =
          engine.graph.terms.firstWhere((t) => t.name == '哥哥').id;
      final tidSis =
          engine.graph.terms.firstWhere((t) => t.name == '妹妹').id;
      final r = engine.resolve(me.id, [tidMother, tidBro, tidSis]);
      expect(r.success, isFalse);
      expect(r.failedIndex, 2);
      expect(r.steps.length, 2);
      expect(r.steps.last.to.name, '舅舅');
    });

    test('起点不存在 → success=false, failedIndex=0', () {
      final r = engine.resolve('e_nonexistent', []);
      expect(r.success, isFalse);
      expect(r.failedIndex, 0);
    });
  });

  group('自定义领域（公司团队等级称呼）', () {
    test('组长 的 上级 = 经理，经理 的 上级 = 总监，链式传递', () {
      final data = RelationGraphData(
        entities: [
          RelationEntity(id: 'e_me', name: '我'),
          RelationEntity(id: 'e_lead', name: '组长'),
          RelationEntity(id: 'e_mgr', name: '经理'),
          RelationEntity(id: 'e_dir', name: '总监'),
        ],
        terms: [
          RelationTerm(id: 't_up', name: '上级'),
        ],
        rules: [
          RelationRule(id: 'r1', fromId: 'e_me', termId: 't_up', toId: 'e_lead'),
          RelationRule(id: 'r2', fromId: 'e_lead', termId: 't_up', toId: 'e_mgr'),
          RelationRule(id: 'r3', fromId: 'e_mgr', termId: 't_up', toId: 'e_dir'),
        ],
      );
      final engine = RelationEngine(data);
      final r = engine.resolve('e_me', ['t_up', 't_up', 't_up']);
      expect(r.success, isTrue);
      expect(r.finalEntity!.name, '总监');
      expect(r.steps.length, 3);
    });
  });

  group('模型序列化', () {
    test('RelationGraphData toMap/fromMap 往返一致', () {
      final original = kinshipPresetData();
      final restored = RelationGraphData.fromMap(original.toMap());
      expect(restored.entities.length, original.entities.length);
      expect(restored.terms.length, original.terms.length);
      expect(restored.rules.length, original.rules.length);
      expect(restored.entities.first.id, original.entities.first.id);
      expect(restored.rules.first.fromId, original.rules.first.fromId);
    });
  });
}
