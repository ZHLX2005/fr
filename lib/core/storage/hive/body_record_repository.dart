import 'package:hive_flutter/hive_flutter.dart';

import '../../body/models/body_record.dart';
import '../box_descriptor.dart';
import '../hive_type_ids.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

class BodyRecordRepository implements HiveRepository {
  static const String _boxName = 'body_records';
  late Box<BodyRecord> _box;
  bool _initialized = false;

  @override
  String get boxName => _boxName;

  Future<void> init() async {
    if (_initialized) return;
    _box = await HiveStore.instance.openTyped<BodyRecord>(
      _boxName,
      adapter: BodyRecordAdapter(),
      typeId: HiveTypeIds.bodyRecord,
    );
    StorageRegistry.register(BoxDescriptor<BodyRecord>(
      name: _boxName,
      displayName: '身体记录',
      typeId: HiveTypeIds.bodyRecord,
      openTyped: () => HiveStore.instance.openTyped<BodyRecord>(
        _boxName,
        adapter: BodyRecordAdapter(),
        typeId: HiveTypeIds.bodyRecord,
      ),
      formatValue: (v) {
        final r = v as BodyRecord;
        final parts = <String>[];
        parts.add('身体部位: ${r.bodyPartId}');
        parts.add('内容: ${r.content}');
        if (r.painLevel != null) parts.add('疼痛等级: ${r.painLevel}');
        parts.add('时间: ${r.createdAt.toString().substring(0, 10)}');
        return parts.join('\n');
      },
    ));
    _initialized = true;
  }

  List<BodyRecord> getRecords(String partId) {
    return _box.values.where((r) => r.bodyPartId == partId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<BodyRecord> getAll() => _box.values.toList();

  Future<void> add(String partId, String content, int? pain) async {
    await _box.add(
      BodyRecord(bodyPartId: partId, content: content, painLevel: pain),
    );
  }

  Future<void> remove(BodyRecord record) async {
    await record.delete();
  }

  Future<void> clear() async => await _box.clear();
}

final bodyRecordRepository = BodyRecordRepository();