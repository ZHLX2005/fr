// 关系库存储 CRUD 单测 —— 覆盖实体/关系词/规则的增删改查、
// 联动清理（删实体/关系词清理引用规则）、持久化往返。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/relation_calc_models.dart';
import 'package:xiaodouzi_fr/lab/demos/relation_calc/relation_calc_store.dart';

void main() {
  late RelationCalcStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = RelationCalcStore.instance;
  });

  group('实体 CRUD', () {
    test('新增实体 → 持久化可读回', () async {
      final next = await store.upsertEntity(
        RelationEntity(id: 'e_1', name: '我', note: '起点'),
      );
      expect(next.entities.length, 1);

      final loaded = await store.load();
      expect(loaded.entities.single.name, '我');
      expect(loaded.entities.single.note, '起点');
    });

    test('同 id 覆盖（改名不改 id）', () async {
      await store.upsertEntity(RelationEntity(id: 'e_1', name: '我'));
      final next = await store.upsertEntity(
        RelationEntity(id: 'e_1', name: '本人', note: '改名'),
      );
      expect(next.entities.length, 1);
      expect(next.entities.single.name, '本人');
    });

    test('删除实体 → 引用它的规则（from/to）一并清理', () async {
      await store.upsertEntity(RelationEntity(id: 'e_me', name: '我'));
      await store.upsertEntity(RelationEntity(id: 'e_f', name: '爸爸'));
      await store.upsertTerm(RelationTerm(id: 't_f', name: '爸爸'));
      await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'e_me', termId: 't_f', toId: 'e_f'),
      );
      await store.upsertRule(
        RelationRule(id: 'r2', fromId: 'e_f', termId: 't_f', toId: 'e_me'),
      );

      // 删起点 e_me：r1（from）与 r2（to）都该消失
      final next = await store.deleteEntity('e_me');
      expect(next.entities.any((e) => e.id == 'e_me'), isFalse);
      expect(next.rules, isEmpty);
    });

    test('删除实体 → 未引用它的规则保留', () async {
      await store.upsertEntity(RelationEntity(id: 'e_me', name: '我'));
      await store.upsertEntity(RelationEntity(id: 'e_f', name: '爸爸'));
      await store.upsertEntity(RelationEntity(id: 'e_g', name: '爷爷'));
      await store.upsertTerm(RelationTerm(id: 't_f', name: '爸爸'));
      await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'e_me', termId: 't_f', toId: 'e_f'),
      );
      await store.upsertRule(
        RelationRule(id: 'r2', fromId: 'e_f', termId: 't_f', toId: 'e_g'),
      );

      final next = await store.deleteEntity('e_g');
      expect(next.rules.length, 1);
      expect(next.rules.single.id, 'r1');
    });
  });

  group('关系词 CRUD', () {
    test('新增/覆盖关系词', () async {
      await store.upsertTerm(RelationTerm(id: 't_f', name: '爸爸'));
      final next = await store.upsertTerm(RelationTerm(id: 't_f', name: '父亲'));
      expect(next.terms.length, 1);
      expect(next.terms.single.name, '父亲');
    });

    test('删除关系词 → 引用它的规则一并清理', () async {
      await store.upsertEntity(RelationEntity(id: 'e_me', name: '我'));
      await store.upsertEntity(RelationEntity(id: 'e_f', name: '爸爸'));
      await store.upsertTerm(RelationTerm(id: 't_f', name: '爸爸'));
      await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'e_me', termId: 't_f', toId: 'e_f'),
      );

      final next = await store.deleteTerm('t_f');
      expect(next.terms, isEmpty);
      expect(next.rules, isEmpty);
    });
  });

  group('规则 CRUD', () {
    test('新增规则 + 覆盖（同 id）', () async {
      await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'a', termId: 't', toId: 'b'),
      );
      final next = await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'a', termId: 't', toId: 'c'),
      );
      expect(next.rules.length, 1);
      expect(next.rules.single.toId, 'c');
    });

    test('删除规则', () async {
      await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'a', termId: 't', toId: 'b'),
      );
      final next = await store.deleteRule('r1');
      expect(next.rules, isEmpty);
    });
  });

  group('持久化', () {
    test('save 后 load 完整往返一致', () async {
      await store.upsertEntity(RelationEntity(id: 'e_me', name: '我'));
      await store.upsertTerm(RelationTerm(id: 't_f', name: '爸爸'));
      await store.upsertRule(
        RelationRule(id: 'r1', fromId: 'e_me', termId: 't_f', toId: 'e_me'),
      );

      final loaded = await store.load();
      expect(loaded.entities.length, 1);
      expect(loaded.terms.length, 1);
      expect(loaded.rules.length, 1);
      expect(loaded.rules.single.fromId, 'e_me');
    });

    test('clear 清空整库', () async {
      await store.upsertEntity(RelationEntity(id: 'e_me', name: '我'));
      await store.clear();
      final loaded = await store.load();
      expect(loaded.entities, isEmpty);
      expect(loaded.terms, isEmpty);
      expect(loaded.rules, isEmpty);
    });

    test('损坏数据 load 返回空快照不崩溃', () async {
      SharedPreferences.setMockInitialValues(
        {RelationCalcStore.kStoreKey: 'not-json{{{'},
      );
      final loaded = await store.load();
      expect(loaded.entities, isEmpty);
    });
  });
}
