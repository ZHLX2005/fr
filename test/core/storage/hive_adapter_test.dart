// Hive TypeAdapter round-trip 验证
//
// 验证 typed box 的 adapter 写入→读出无损：
// - BodyRecord：hive_generator 生成的 adapter（手写→生成的迁移后回归）
//
// 历史：Event / Person 的手写 adapter 测试曾在此文件中存在；calendar demo
// 已下线，对应测试一并删除。BodyRecord 测试保留作为 typed box 的回归基线。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:xiaodouzi_fr/core/body/models/body_record.dart';
import 'package:xiaodouzi_fr/core/storage/hive_type_ids.dart';

void main() {
  // adapter 注册是全局的，整个测试只注册一次
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_adapter_test_');
    Hive.init(tempDir.path);
    Hive.registerAdapter(BodyRecordAdapter());
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

  group('HiveTypeIds 集中表', () {
    test('typeId 数值稳定（磁盘格式契约）', () {
      // 这些数字是磁盘数据的二进制契约，改动会让旧数据不可读
      expect(HiveTypeIds.bodyRecord, 0);
    });
  });
}