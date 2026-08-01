// Hive TypeAdapter round-trip 验证
//
// 验证三个 typed box 的 adapter 写入→读出无损：
// - BodyRecord：hive_generator 生成的 adapter（手写→生成的迁移后回归）
// - Event / Person：手写 adapter（枚举按 index 序列化，保证既有数据可读）
//
// 既有数据二进制兼容性说明：Event/Person 的手写 adapter 与重构前字节布局
// 完全一致（typeId 由 HiveTypeIds 解析为同样的 0/90/91，枚举写 .index），
// 故磁盘上的旧数据读取不受影响。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:xiaodouzi_fr/core/body/models/body_record.dart';
import 'package:xiaodouzi_fr/core/storage/hive_type_ids.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/event_adapter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/person_adapter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/recurrence.dart';

void main() {
  // adapter 注册是全局的，整个测试只注册一次
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_adapter_test_');
    Hive.init(tempDir.path);
    Hive.registerAdapter(BodyRecordAdapter());
    Hive.registerAdapter(EventAdapter());
    Hive.registerAdapter(PersonAdapter());
  });

  tearDown(() async {
    // 每个 test 之间清空 box 文件，保留 adapter 注册
    await Hive.deleteFromDisk();
  });

  group('BodyRecord (generated adapter)', () {
    test('round-trip 完整字段', () async {
      final box = await Hive.openBox<BodyRecord>('body_records');
      final original = BodyRecord(
        bodyPartId: 'head',
        content: '头痛',
        painLevel: 3,
        createdAt: DateTime(2026, 7, 1, 10, 30),
      );
      await box.put('r1', original);

      final read = box.get('r1')!;
      expect(read.bodyPartId, 'head');
      expect(read.content, '头痛');
      expect(read.painLevel, 3);
      expect(read.createdAt, DateTime(2026, 7, 1, 10, 30));
    });

    test('painLevel 可空（null）', () async {
      final box = await Hive.openBox<BodyRecord>('body_records');
      await box.put('r2', BodyRecord(bodyPartId: 'knee', content: '无疼痛'));

      final read = box.get('r2')!;
      expect(read.painLevel, isNull);
    });
  });

  group('Event (hand-written adapter, 含枚举)', () {
    test('round-trip 经 toJson 等价', () async {
      final box = await Hive.openBox<Event>('calendarEvents');
      final original = Event(
        id: 'e1',
        type: EventType.birthday,
        title: '生日',
        system: CalendarSystem.lunar,
        year: 1990,
        month: 8,
        day: 15,
        recurrence: Recurrence.yearly,
        colorTag: ColorTag.red,
        createdAt: DateTime(2026, 1, 1),
        isLeap: true,
        note: '备注',
        personId: 'p1',
      );
      await box.put('e1', original);

      final read = box.get('e1')!;
      // Event 无 ==，用 toJson 比较序列化结果
      expect(read.toJson(), original.toJson());
    });

    test('枚举索引稳定（birthday=0, lunar=1）', () async {
      // 防止枚举顺序被无意改动破坏既有数据
      expect(EventType.birthday.index, 0);
      expect(CalendarSystem.lunar.index, 1);
    });
  });

  group('Person (hand-written adapter, 含枚举)', () {
    test('round-trip 经 toJson 等价', () async {
      final box = await Hive.openBox<Person>('calendarPeople');
      final original = Person(
        id: 'p1',
        name: '张三',
        relation: PersonRelation.family,
        createdAt: DateTime(2026, 1, 1),
        avatarEmoji: '😀',
        note: '父亲',
      );
      await box.put('p1', original);

      final read = box.get('p1')!;
      expect(read.toJson(), original.toJson());
    });
  });

  group('HiveTypeIds 集中表', () {
    test('typeId 数值稳定（磁盘格式契约）', () {
      // 这些数字是磁盘数据的二进制契约，改动会让旧数据不可读
      expect(HiveTypeIds.bodyRecord, 0);
      expect(HiveTypeIds.calendarEvent, 90);
      expect(HiveTypeIds.calendarPerson, 91);
    });
  });
}
