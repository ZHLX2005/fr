import 'package:hive_flutter/hive_flutter.dart';
import 'body_record.dart';
import '../../storage/box_descriptor.dart';
import '../../storage/storage_registry.dart';

class BodyRecordRepo {
  static const String _boxName = 'body_records';
  late Box<BodyRecord> _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(BodyRecordAdapter());
    }
    _box = await Hive.openBox<BodyRecord>(_boxName);
    StorageRegistry.register(BoxDescriptor<BodyRecord>(
      name: _boxName,
      displayName: '身体记录',
      typeId: 0,
      openTyped: () => Hive.openBox<BodyRecord>(_boxName),
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

final bodyRecordRepo = BodyRecordRepo();
